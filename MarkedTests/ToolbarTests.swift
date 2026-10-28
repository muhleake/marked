import AppKit
import XCTest
@testable import Marked

@MainActor
final class ToolbarTests: XCTestCase {
    private var tempDir: URL!
    private var opened: [NSDocument] = []

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkedToolbarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        for doc in opened { doc.close() }
        opened.removeAll()
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func openWindow(_ name: String, _ text: String) async throws -> DocumentWindowController {
        let url = tempDir.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        let (doc, _) = try await NSDocumentController.shared.openDocument(withContentsOf: url, display: true)
        opened.append(doc)
        let controller = try XCTUnwrap(doc.windowControllers.first as? DocumentWindowController)
        controller.window?.makeKeyAndOrderFront(nil)
        controller.window?.makeFirstResponder(controller.editorTextView)
        return controller
    }

    private func formatItem(_ action: MarkdownAction) throws -> NSMenuItem {
        let format = try XCTUnwrap(NSApp.mainMenu?.item(withTitle: "Format")?.submenu)
        func find(_ menu: NSMenu) -> NSMenuItem? {
            for item in menu.items {
                if item.action == #selector(DocumentWindowController.applyMarkdownAction(_:)), item.tag == action.rawValue { return item }
                if let sub = item.submenu, let found = find(sub) { return found }
            }
            return nil
        }
        return try XCTUnwrap(find(format), "no Format item for \(action)")
    }

    /// Runs `body` as one undo group, the way one key event or click is in the app
    /// (XCTest never ends the automatic per-event group; see DocumentTests).
    private func asOneEvent(_ controller: DocumentWindowController, _ body: () throws -> Void) rethrows {
        let undo = controller.markdownDocument!.undoManager!
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        defer { undo.endUndoGrouping(); undo.groupsByEvent = true }
        try body()
    }

    // MARK: - Toolbar

    func testToolbarItems() async throws {
        let controller = try await openWindow("tb.md", "x")
        let toolbar = try XCTUnwrap(controller.window?.toolbar)
        XCTAssertTrue(toolbar.allowsUserCustomization)
        let ids = toolbar.items.map(\.itemIdentifier)
        for action in [MarkdownAction.bold, .italic, .strikethrough, .underline, .highlight, .bulletList, .numberedList, .taskList, .quote,
                       .inlineCode, .codeBlock, .link, .image, .table, .horizontalRule] {
            XCTAssertTrue(ids.contains(ToolbarController.identifier(for: action)), "missing \(action)")
        }
        let heading = try XCTUnwrap(toolbar.items.first { $0.itemIdentifier == ToolbarController.headingItem } as? NSMenuToolbarItem)
        XCTAssertEqual(heading.menu.items.map(\.title), (1...6).map { "Heading \($0)" })
        let layout = try XCTUnwrap(toolbar.items.first { $0.itemIdentifier == ToolbarController.layoutItem } as? NSToolbarItemGroup)
        XCTAssertEqual(layout.subitems.count, 3)
        for item in toolbar.items where item.action == #selector(DocumentWindowController.applyMarkdownAction(_:)) {
            XCTAssertNotNil(item.image, "\(item.itemIdentifier) has no SF Symbol")
        }
    }

    func testTextColorMenuAppliesReplacesAndRemoves() async throws {
        let controller = try await openWindow("color.md", "word")
        let textView = try XCTUnwrap(controller.editorTextView)
        let toolbarItem = try XCTUnwrap(controller.window?.toolbar?.items.first { $0.itemIdentifier == ToolbarController.textColorItem } as? NSMenuToolbarItem)
        XCTAssertEqual(toolbarItem.menu.items.filter { $0.representedObject != nil }.count, TextColor.allCases.count)
        let format = try XCTUnwrap(NSApp.mainMenu?.item(withTitle: "Format")?.submenu)
        let colors = try XCTUnwrap(format.item(withTitle: "Text Color")?.submenu)
        let red = try XCTUnwrap(colors.item(withTitle: "Red")), blue = try XCTUnwrap(colors.item(withTitle: "Blue"))
        let remove = try XCTUnwrap(colors.item(withTitle: "Remove Color"))
        XCTAssertTrue(controller.validateMenuItem(red))

        textView.setSelectedRange(NSRange(location: 0, length: 4))
        asOneEvent(controller) { controller.applyTextColor(red) }
        XCTAssertEqual(textView.string, "<span style=\"color: #e5484d\">word</span>")
        asOneEvent(controller) { controller.applyTextColor(blue) }
        XCTAssertEqual(textView.string, "<span style=\"color: #0090ff\">word</span>")
        asOneEvent(controller) { controller.applyTextColor(remove) }
        XCTAssertEqual(textView.string, "word")
        controller.markdownDocument?.undoManager?.undo()
        XCTAssertEqual(textView.string, "<span style=\"color: #0090ff\">word</span>", "each color change is one undo step")
    }

    func testTextColorDisabledForPlainText() async throws {
        let controller = try await openWindow("color.txt", "x")
        let red = try XCTUnwrap(NSApp.mainMenu?.item(withTitle: "Format")?.submenu?.item(withTitle: "Text Color")?.submenu?.item(withTitle: "Red"))
        XCTAssertFalse(controller.validateMenuItem(red))
    }

    func testToolbarLayoutControlFollowsLayout() async throws {
        let controller = try await openWindow("seg.md", "x")
        let layout = try XCTUnwrap(controller.window?.toolbar?.items.first { $0.itemIdentifier == ToolbarController.layoutItem } as? NSToolbarItemGroup)
        controller.layout = .split
        XCTAssertEqual(layout.selectedIndex, 0)
        controller.cyclePreviewLayout(nil)
        XCTAssertEqual(layout.selectedIndex, 1)
        controller.cyclePreviewLayout(nil)
        XCTAssertEqual(layout.selectedIndex, 2)
    }

    // MARK: - Actions

    /// Every action applies, and one undo restores the text as it was before it (not
    /// merged with earlier typing); redo re-applies.
    func testEveryActionAppliesAndUndoesInOneStep() async throws {
        let controller = try await openWindow("all.md", "")
        let textView = try XCTUnwrap(controller.editorTextView)
        let undo = try XCTUnwrap(controller.markdownDocument?.undoManager)

        for action in MarkdownAction.allCases {
            controller.markdownDocument?.replaceText(with: "")
            undo.removeAllActions()
            // Type a word (its own undo step), select it, apply the action (another step).
            asOneEvent(controller) { textView.insertText("word", replacementRange: NSRange(location: 0, length: 0)) }
            textView.setSelectedRange(NSRange(location: 0, length: 4))
            let item = try formatItem(action)
            XCTAssertTrue(controller.validateMenuItem(item), "\(action) disabled")
            asOneEvent(controller) { controller.applyMarkdownAction(item) }
            let applied = textView.string
            let appliedSelection = textView.selectedRange()
            XCTAssertNotEqual(applied, "word", "\(action) changed nothing")
            XCTAssertEqual(undo.undoActionName, action.title)

            undo.undo()
            XCTAssertEqual(textView.string, "word", "\(action): one undo should restore the typed text")
            undo.redo()
            XCTAssertEqual(textView.string, applied, "\(action): redo")

            // Toggle off from the resulting selection (rules and tables are inserted, so skip those).
            if ![.table, .horizontalRule, .codeBlock, .link, .image].contains(action) {
                textView.setSelectedRange(appliedSelection)
                asOneEvent(controller) { controller.applyMarkdownAction(item) }
                XCTAssertEqual(textView.string, "word", "\(action) should toggle off")
            }
        }
    }

    func testShortcutsTriggerActions() async throws {
        let controller = try await openWindow("keys.md", "")
        let window = try XCTUnwrap(controller.window)
        let textView = try XCTUnwrap(controller.editorTextView)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)

        // The test host is never the active app, so there is no key window for
        // first-responder actions. Target the Format items at this window directly;
        // the key-equivalent matching under test is unchanged.
        let items = try MarkdownAction.allCases.map { try formatItem($0) }
        items.forEach { $0.target = controller }
        defer { items.forEach { $0.target = nil } }
        for action in MarkdownAction.allCases {
            controller.markdownDocument?.replaceText(with: "word")
            textView.setSelectedRange(NSRange(location: 0, length: 4))
            let (key, modifiers) = action.shortcut
            var flags = modifiers
            if key != key.lowercased() { flags.insert(.shift) }
            if ["*", "&", ">", "_"].contains(key) { flags.insert(.shift) }
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: key,
                charactersIgnoringModifiers: modifiers.contains(.option) ? key : key, isARepeat: false, keyCode: 0))
            let handled = NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
            XCTAssertTrue(handled, "\(action) shortcut \(ToolbarController.shortcutDescription(action)) not handled")
            XCTAssertNotEqual(textView.string, "word", "\(action) shortcut did nothing")
        }
    }

    func testFormattingDisabledForPlainTextUntilTreatedAsMarkdown() async throws {
        let controller = try await openWindow("p.txt", "plain")
        let bold = try formatItem(.bold)
        XCTAssertFalse(controller.validateMenuItem(bold))
        let toolbarBold = try XCTUnwrap(controller.window?.toolbar?.items.first { $0.itemIdentifier == ToolbarController.identifier(for: .bold) })
        XCTAssertFalse(controller.validateToolbarItem(toolbarBold))

        controller.toggleTreatAsMarkdown(nil)
        XCTAssertTrue(controller.validateMenuItem(bold))
        XCTAssertTrue(controller.validateToolbarItem(toolbarBold))
    }

    func testFormattingDisabledInPreviewOnly() async throws {
        let controller = try await openWindow("po.md", "x")
        controller.layout = .previewOnly
        XCTAssertFalse(controller.validateMenuItem(try formatItem(.italic)))
        controller.layout = .split
        XCTAssertTrue(controller.validateMenuItem(try formatItem(.italic)))
    }

    // MARK: - Shortcut conflicts

    /// No two menu items (including the ones AppKit adds at runtime) share a shortcut.
    func testNoDuplicateKeyEquivalents() async throws {
        _ = try await openWindow("menus.md", "x")
        var seen: [String: String] = [:]
        var duplicates: [String] = []
        func walk(_ menu: NSMenu, path: String) {
            menu.update()
            for item in menu.items {
                let key = item.keyEquivalent
                if !key.isEmpty, !item.isAlternate {
                    var mods = item.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control])
                    var base = key
                    if key.count == 1, key != key.lowercased() { mods.insert(.shift); base = key.lowercased() }
                    let signature = "\(mods.rawValue)-\(base)"
                    let name = "\(path) ▸ \(item.title)"
                    if let other = seen[signature] { duplicates.append("\(other) vs \(name)") } else { seen[signature] = name }
                }
                if let sub = item.submenu { walk(sub, path: "\(path) ▸ \(item.title)") }
            }
        }
        walk(try XCTUnwrap(NSApp.mainMenu), path: "")
        XCTAssertEqual(duplicates, [], "conflicting shortcuts")
        print("SHORTCUTS: \(seen.count) unique key equivalents")
    }
}
