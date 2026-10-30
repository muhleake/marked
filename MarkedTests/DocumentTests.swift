import AppKit
import XCTest
@testable import Marked

/// In-process integration tests: the test bundle runs inside Marked.app.
@MainActor
final class DocumentTests: XCTestCase {
    private var tempDir: URL!
    private var opened: [NSDocument] = []

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkedTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        for doc in opened { doc.close() }
        opened.removeAll()
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func write(_ name: String, _ data: Data) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func open(_ url: URL, display: Bool = false) async throws -> MarkdownDocument {
        let (doc, _) = try await NSDocumentController.shared.openDocument(withContentsOf: url, display: display)
        opened.append(doc)
        return try XCTUnwrap(doc as? MarkdownDocument)
    }

    private func save(_ doc: NSDocument, to url: URL, type: String, op: NSDocument.SaveOperationType = .saveAsOperation) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            doc.save(to: url, ofType: type, for: op) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    /// Types by posting real key events through NSApp, so NSTextView, undo grouping
    /// and the document's change count all run as they do for a person typing.
    private func type(_ text: String, in doc: MarkdownDocument) async throws {
        let controller = try XCTUnwrap(doc.windowControllers.first as? DocumentWindowController)
        let window = try XCTUnwrap(controller.window)
        let textView = try XCTUnwrap(controller.editorTextView)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        // In the app, NSApplication closes the automatic undo group after each event.
        // XCTest runs inside a run-loop callout where that never fires, so group explicitly.
        let undo = try XCTUnwrap(doc.undoManager)
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        defer { undo.groupsByEvent = true }
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        for character in text {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                let event = try XCTUnwrap(NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil,
                    characters: String(character), charactersIgnoringModifiers: String(character),
                    isARepeat: false, keyCode: 0))
                NSApp.postEvent(event, atStart: false)
            }
        }
        let deadline = Date().addingTimeInterval(3)
        while textView.string.hasSuffix(text) == false, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        textView.breakUndoCoalescing()
        undo.endUndoGrouping()
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    // MARK: - Types

    func testMarkdownExtensionsOpenAsMarkdown() async throws {
        for ext in ["md", "markdown", "mdown"] {
            let doc = try await open(try write("a.\(ext)", Data("# Hi".utf8)))
            XCTAssertEqual(doc.fileType, MarkdownDocument.markdownType, ext)
            XCTAssertFalse(doc.isPlainText, ext)
            XCTAssertEqual(doc.text, "# Hi")
        }
    }

    func testTxtOpensAsPlainText() async throws {
        let doc = try await open(try write("notes.txt", Data("plain".utf8)))
        XCTAssertEqual(doc.fileType, MarkdownDocument.plainTextType)
        XCTAssertTrue(doc.isPlainText)
    }

    func testNewDocumentDefaultsToMarkdown() throws {
        let doc = try NSDocumentController.shared.makeUntitledDocument(ofType: NSDocumentController.shared.defaultType!)
        opened.append(doc)
        XCTAssertEqual(doc.fileType, MarkdownDocument.markdownType)
        XCTAssertEqual(doc.fileNameExtension(forType: doc.fileType!, saveOperation: .saveOperation), "md")
        XCTAssertEqual(doc.writableTypes(for: .saveAsOperation), [MarkdownDocument.markdownType, MarkdownDocument.plainTextType])
        XCTAssertTrue(MarkdownDocument.autosavesInPlace)
    }

    // MARK: - Windows

    func testMarkdownWindowShowsSplitAndTxtWindowCollapsesPreview() async throws {
        let md = try await open(try write("a.md", Data("# A".utf8)), display: true)
        let txt = try await open(try write("b.txt", Data("B".utf8)), display: true)
        let mdController = try XCTUnwrap(md.windowControllers.first as? DocumentWindowController)
        let txtController = try XCTUnwrap(txt.windowControllers.first as? DocumentWindowController)
        XCTAssertEqual(mdController.splitController.layout, Preferences.defaultLayout)
        XCTAssertEqual(txtController.splitController.layout, .editorOnly)
        XCTAssertTrue(txtController.splitController.splitViewItems[1].isCollapsed)
        XCTAssertFalse(txtController.isMarkdownEnabled)
        XCTAssertEqual(mdController.window?.tabbingMode, .automatic)
    }

    func testEditorConfiguration() async throws {
        let doc = try await open(try write("c.md", Data("x".utf8)), display: true)
        let textView = try XCTUnwrap((doc.windowControllers.first as? DocumentWindowController)?.editorTextView)
        XCTAssertTrue(textView.textStorage === doc.textStorage)
        XCTAssertFalse(textView.isRichText)
        XCTAssertTrue(textView.usesFindBar)
        XCTAssertTrue(textView.allowsUndo)
        XCTAssertTrue(textView.isContinuousSpellCheckingEnabled)
        XCTAssertFalse(textView.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(textView.isAutomaticDashSubstitutionEnabled)
        XCTAssertFalse(textView.isAutomaticTextReplacementEnabled)
        XCTAssertTrue(textView.textContainer?.widthTracksTextView ?? false)
        XCTAssertTrue(textView.font?.isFixedPitch ?? false)
        XCTAssertEqual(textView.font?.pointSize, Preferences.editorFontSize)
    }

    func testTypingStraightQuotesStaysStraight() async throws {
        let doc = try await open(try write("q.md", Data("".utf8)), display: true)
        try await type("\"quotes\" and 'single' -- dash", in: doc)
        XCTAssertEqual(doc.text, "\"quotes\" and 'single' -- dash")
    }

    // MARK: - Save, reopen, revert, duplicate

    func testEditSaveReopen() async throws {
        let url = try write("edit.md", Data("# Title\n".utf8))
        let doc = try await open(url, display: true)
        try await type("More text", in: doc)
        XCTAssertTrue(doc.isDocumentEdited)
        try await save(doc, to: url, type: doc.fileType!, op: .saveOperation)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "# Title\nMore text")
        doc.close()
        opened.removeAll()

        let reopened = try await open(url)
        XCTAssertEqual(reopened.text, "# Title\nMore text")
    }

    func testNewDocumentSavesUTF8Markdown() async throws {
        let doc = try NSDocumentController.shared.makeUntitledDocument(ofType: MarkdownDocument.markdownType) as! MarkdownDocument
        opened.append(doc)
        doc.replaceText(with: "naïve café")
        let url = tempDir.appendingPathComponent("Untitled.md")
        try await save(doc, to: url, type: MarkdownDocument.markdownType)
        XCTAssertEqual(try Data(contentsOf: url), Data("naïve café".utf8))
    }

    func testSaveAsTxtChangesType() async throws {
        let doc = try await open(try write("t.md", Data("text".utf8)), display: true)
        let url = tempDir.appendingPathComponent("t.txt")
        try await save(doc, to: url, type: MarkdownDocument.plainTextType)
        XCTAssertEqual(doc.fileType, MarkdownDocument.plainTextType)
        XCTAssertTrue(doc.isPlainText)
        let controller = try XCTUnwrap(doc.windowControllers.first as? DocumentWindowController)
        XCTAssertEqual(controller.splitController.layout, .editorOnly)
    }

    func testCRLFFileSavesBackAsCRLF() async throws {
        let original = Data("one\r\ntwo\r\n".utf8)
        let url = try write("crlf.md", original)
        let doc = try await open(url, display: true)
        XCTAssertEqual(doc.text, "one\ntwo\n")
        try await type("three", in: doc)
        try await save(doc, to: url, type: doc.fileType!, op: .saveOperation)
        XCTAssertEqual(try Data(contentsOf: url), Data("one\r\ntwo\r\nthree".utf8))
    }

    func testWindows1252FileOpensClean() async throws {
        let doc = try await open(try write("w.txt", Data([0x63, 0x61, 0x66, 0xE9, 0x20, 0x93, 0x78, 0x94])))
        XCTAssertEqual(doc.text, "café “x”")
    }

    func testRevertRestoresSavedText() async throws {
        let url = try write("rev.md", Data("saved".utf8))
        let doc = try await open(url, display: true)
        try await type(" plus edits", in: doc)
        XCTAssertEqual(doc.text, "saved plus edits")
        try doc.revert(toContentsOf: url, ofType: doc.fileType!)
        XCTAssertEqual(doc.text, "saved")
        let textView = try XCTUnwrap((doc.windowControllers.first as? DocumentWindowController)?.editorTextView)
        XCTAssertEqual(textView.string, "saved")
    }

    func testDuplicate() async throws {
        let doc = try await open(try write("dup.md", Data("copy me".utf8)))
        let copy = try XCTUnwrap(try doc.duplicate() as? MarkdownDocument)
        opened.append(copy)
        XCTAssertEqual(copy.text, "copy me")
        XCTAssertNil(copy.fileURL)
        XCTAssertEqual(copy.fileType, MarkdownDocument.markdownType)
    }

    func testOpenRecentRecordsDocument() async throws {
        let url = try write("recent.md", Data("r".utf8))
        _ = try await open(url, display: true)
        let recents = NSDocumentController.shared.recentDocumentURLs.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        XCTAssertTrue(recents.contains(url.standardizedFileURL.resolvingSymlinksInPath()))
    }

    func testUndoRevertsTyping() async throws {
        let doc = try await open(try write("undo.md", Data("base".utf8)), display: true)
        try await type("!", in: doc)
        let textView = try XCTUnwrap((doc.windowControllers.first as? DocumentWindowController)?.editorTextView)
        XCTAssertTrue(textView.undoManager === doc.undoManager)
        XCTAssertTrue(doc.isDocumentEdited)
        doc.undoManager?.undo()
        XCTAssertEqual(doc.text, "base")
        XCTAssertFalse(doc.isDocumentEdited, "undo back to the saved text clears Edited")
    }

    // MARK: - Menus

    func testOpenRecentMenuIsPopulated() async throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build.noindex/test-files", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("menu-recent.md")
        try Data("r".utf8).write(to: url)
        _ = try await open(url, display: true)
        let file = try XCTUnwrap(NSApp.mainMenu?.item(withTitle: "File")?.submenu)
        let recent = try XCTUnwrap(file.item(withTitle: "Open Recent")?.submenu)
        // Menu tracking calls this on AppKit's recent-documents delegate when the menu opens.
        let delegate = try XCTUnwrap(recent.delegate as? NSObject, "AppKit did not adopt the Open Recent menu")
        let update = NSSelectorFromString("updateMenu:withEvent:withFlags:")
        guard delegate.responds(to: update) else { throw XCTSkip("AppKit's recent-menu hook changed") }
        typealias UpdateFn = @convention(c) (NSObject, Selector, NSMenu, NSEvent?, Int) -> Void
        unsafeBitCast(delegate.method(for: update), to: UpdateFn.self)(delegate, update, recent, nil, 0)
        let titles = recent.items.map(\.title)
        XCTAssertTrue(titles.contains("menu-recent.md"), "Open Recent items: \(titles)")
        XCTAssertEqual(titles.last, "Clear Menu")
    }

    func testMainMenuMatchesReference() throws {
        let titles = NSApp.mainMenu?.items.map(\.title) ?? []
        XCTAssertEqual(Array(titles.dropFirst()), ["File", "Edit", "Format", "View", "Window", "Help"])
        let file = try XCTUnwrap(NSApp.mainMenu?.item(withTitle: "File")?.submenu)
        XCTAssertNotNil(file.item(withTitle: "Open Recent")?.submenu)
        XCTAssertEqual(file.item(withTitle: "Save As…")?.keyEquivalent, "S")
        let edit = try XCTUnwrap(NSApp.mainMenu?.item(withTitle: "Edit")?.submenu)
        let find = try XCTUnwrap(edit.item(withTitle: "Find")?.submenu)
        XCTAssertEqual(find.item(withTitle: "Use Selection for Find")?.keyEquivalent, "e")
        XCTAssertNotNil(edit.item(withTitle: "Substitutions"))
        XCTAssertNotNil(edit.item(withTitle: "Spelling and Grammar"))
    }
}
