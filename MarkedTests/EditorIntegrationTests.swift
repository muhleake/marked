import AppKit
import XCTest
@testable import Marked

@MainActor
final class EditorIntegrationTests: XCTestCase {
    private var opened: [NSDocument] = []
    private var savedFontSize: CGFloat = 13
    private var savedDisplay = (lineNumbers: false, indentGuides: false)

    override func setUp() async throws {
        savedFontSize = Preferences.editorFontSize
        savedDisplay = (Preferences.showLineNumbers, Preferences.showIndentGuides)
    }

    override func tearDown() async throws {
        opened.forEach { $0.close() }
        opened.removeAll()
        Preferences.editorFontSize = savedFontSize
        Preferences.showLineNumbers = savedDisplay.lineNumbers
        Preferences.showIndentGuides = savedDisplay.indentGuides
    }

    private func window(_ name: String, _ text: String) async throws -> DocumentWindowController {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try Data(text.utf8).write(to: url)
        let (doc, _) = try await NSDocumentController.shared.openDocument(withContentsOf: url, display: true)
        opened.append(doc)
        return try XCTUnwrap(doc.windowControllers.first as? DocumentWindowController)
    }

    /// Regression: an auto-hiding scroll bar changes the text width, which re-wraps the
    /// text and can loop forever when "Show scroll bars" is set to Always.
    func testScrollBarNeverChangesTheTextWidth() async throws {
        let controller = try await window("scroll.md", "short")
        let editor = controller.splitController.editorController
        let scrollView = try XCTUnwrap(editor.scrollView)
        XCTAssertFalse(scrollView.autohidesScrollers)

        scrollView.scrollerStyle = .legacy
        scrollView.tile()
        let width = scrollView.contentView.frame.width
        let long = String(repeating: "A line of text that is long enough to wrap in the editor pane.\n", count: 200)
        for text in [long, "short", long] {
            controller.markdownDocument?.replaceText(with: text)
            editor.textView.layoutManager?.ensureLayout(for: editor.textView.textContainer!)
            scrollView.tile()
            XCTAssertEqual(scrollView.contentView.frame.width, width)
        }
    }

    func testReturnContinuesListInEditor() async throws {
        let controller = try await window("l.md", "- one")
        let textView = try XCTUnwrap(controller.editorTextView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(textView.string, "- one\n- ")
        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(textView.string, "- one\n")
    }

    func testReturnInPlainTextIsPlain() async throws {
        let controller = try await window("l.txt", "- one")
        let textView = try XCTUnwrap(controller.editorTextView)
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(textView.string, "- one\n")
        XCTAssertFalse(controller.splitController.editorController.highlighter.isEnabled)
        controller.toggleTreatAsMarkdown(nil)
        XCTAssertTrue(controller.splitController.editorController.highlighter.isEnabled)
    }

    func testStatusBarCounts() async throws {
        let controller = try await window("c.md", "hello world")
        let editor = controller.splitController.editorController
        let deadline = Date().addingTimeInterval(2)
        while editor.statusLabel.stringValue.isEmpty, Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(editor.statusLabel.stringValue, "2 words · 11 characters · 1 line")
        controller.markdownDocument?.textStorage.replaceCharacters(in: NSRange(location: 11, length: 0), with: "\nagain")
        while !editor.statusLabel.stringValue.hasPrefix("3"), Date() < deadline.addingTimeInterval(2) { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(editor.statusLabel.stringValue, "3 words · 17 characters · 2 lines")
    }

    func testFontSizeBiggerSmallerPersists() async throws {
        let controller = try await window("f.md", "# big")
        Preferences.editorFontSize = 13
        let app = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        app.makeTextBigger(nil)
        app.makeTextBigger(nil)
        XCTAssertEqual(Preferences.editorFontSize, 15)
        XCTAssertEqual(UserDefaults.standard.double(forKey: Preferences.Key.editorFontSize), 15)
        let textView = try XCTUnwrap(controller.editorTextView)
        XCTAssertEqual((textView.textStorage?.attribute(.font, at: 3, effectiveRange: nil) as? NSFont)?.pointSize, 15)
        XCTAssertTrue(controller.splitController.editorController.highlighter.isEnabled)
        app.makeTextSmaller(nil)
        XCTAssertEqual(Preferences.editorFontSize, 14)
        Preferences.editorFontSize = 100
        XCTAssertEqual(Preferences.editorFontSize, Preferences.fontSizeRange.upperBound)
    }

    // MARK: - Line numbers and indentation guides

    func testLineNumbersAndGuidesAreOffByDefault() {
        let registered = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
        XCTAssertEqual(registered[Preferences.Key.showLineNumbers] as? Bool, false)
        XCTAssertEqual(registered[Preferences.Key.showIndentGuides] as? Bool, false)
    }

    func testViewMenuTogglesLineNumbersAndGuidesInEveryWindow() async throws {
        Preferences.showLineNumbers = false
        Preferences.showIndentGuides = false
        let editors = [try await window("a.md", "a"), try await window("b.txt", "b")].map { $0.splitController.editorController }
        XCTAssertTrue(editors.allSatisfy { !$0.scrollView.rulersVisible && !$0.textView.showsIndentGuides })

        let app = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        let numbers = NSMenuItem(title: "", action: #selector(AppDelegate.toggleLineNumbers(_:)), keyEquivalent: "")
        let guides = NSMenuItem(title: "", action: #selector(AppDelegate.toggleIndentGuides(_:)), keyEquivalent: "")
        app.toggleLineNumbers(nil)
        app.toggleIndentGuides(nil)
        XCTAssertTrue(editors.allSatisfy { $0.scrollView.rulersVisible && $0.textView.showsIndentGuides })
        XCTAssertTrue(app.validateMenuItem(numbers) && app.validateMenuItem(guides))
        XCTAssertEqual(numbers.state, .on)
        XCTAssertEqual(guides.state, .on)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: Preferences.Key.showLineNumbers))

        app.toggleLineNumbers(nil)
        XCTAssertTrue(editors.allSatisfy { !$0.scrollView.rulersVisible && $0.textView.showsIndentGuides })
        _ = app.validateMenuItem(numbers)
        XCTAssertEqual(numbers.state, .off)
    }

    func testLineNumbersCountFileLinesNotWrappedRows() async throws {
        Preferences.showLineNumbers = true
        let long = String(repeating: "wrapping words ", count: 60)
        let controller = try await window("n.md", "first\n\(long)\nlast\n")
        let editor = controller.splitController.editorController
        let textView = try XCTUnwrap(editor.textView)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let labels = editor.lineNumbers.labels(in: textView.bounds)
        XCTAssertEqual(labels.map(\.number), [1, 2, 3, 4], "one number per line, plus the empty last line")
        let rowHeight = labels[1].top - labels[0].top
        XCTAssertGreaterThan(labels[2].top - labels[1].top, rowHeight * 1.5, "line 2 wraps onto more rows")
        XCTAssertGreaterThan(editor.lineNumbers.ruleThickness, 0)
    }

    func testRulerWidensForMoreDigits() async throws {
        Preferences.showLineNumbers = true
        let controller = try await window("w.md", "one")
        let ruler = controller.splitController.editorController.lineNumbers!
        let narrow = ruler.ruleThickness
        ruler.lineCount = 99
        XCTAssertEqual(ruler.ruleThickness, narrow, "room for two digits from the start")
        ruler.lineCount = 12_345
        XCTAssertGreaterThan(ruler.ruleThickness, narrow)
    }

    func testIndentColumns() {
        func columns(_ line: String) -> Int { EditorTextView.indentColumns(in: line as NSString, from: 0) }
        XCTAssertEqual(columns("text"), 0)
        XCTAssertEqual(columns("    - item"), 4)
        XCTAssertEqual(columns("        x"), 8)
        XCTAssertEqual(columns("\tx"), 4)
        XCTAssertEqual(columns("  \tx"), 4, "a tab moves to the next indent stop")
        XCTAssertEqual(columns("      x"), 6)
        XCTAssertEqual(columns("        "), 0, "whitespace-only lines get no guides")
        XCTAssertEqual(columns("    \nnext"), 0)
    }

    func testLineTableStaysCorrectThroughEdits() async throws {
        let controller = try await window("t.md", "one\ntwo\n\nthree")
        let editor = controller.splitController.editorController
        let storage = editor.textStorage
        func check(_ label: String) {
            XCTAssertEqual(editor.lineStartOffsets(), EditorViewController.lineStarts(of: storage.string as NSString), label)
        }
        check("initial")
        let edits: [(NSRange, String)] = [
            (NSRange(location: 3, length: 0), "\nnew"), (NSRange(location: 0, length: 4), ""),
            (NSRange(location: 2, length: 5), "a\nb\nc"), (NSRange(location: storage.length, length: 0), "\n"),
            (NSRange(location: 0, length: 0), "\n\n"), (NSRange(location: 1, length: 3), "x"),
        ]
        for (range, text) in edits {
            storage.replaceCharacters(in: range, with: text)
            check("after replacing \(range) with \(text.debugDescription)")
        }
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: 1), with: "1\n2")
        storage.replaceCharacters(in: NSRange(location: storage.length - 1, length: 1), with: "")
        storage.endEditing()
        check("after a grouped edit")
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: "")
        check("empty")
        XCTAssertEqual(editor.lineIndex(ofCharacterAt: 0), 0)
    }
}
