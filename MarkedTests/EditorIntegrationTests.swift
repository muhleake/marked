import AppKit
import XCTest
@testable import Marked

@MainActor
final class EditorIntegrationTests: XCTestCase {
    private var opened: [NSDocument] = []
    private var savedFontSize: CGFloat = 13

    override func setUp() async throws { savedFontSize = Preferences.editorFontSize }

    override func tearDown() async throws {
        opened.forEach { $0.close() }
        opened.removeAll()
        Preferences.editorFontSize = savedFontSize
    }

    private func window(_ name: String, _ text: String) async throws -> DocumentWindowController {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try Data(text.utf8).write(to: url)
        let (doc, _) = try await NSDocumentController.shared.openDocument(withContentsOf: url, display: true)
        opened.append(doc)
        return try XCTUnwrap(doc.windowControllers.first as? DocumentWindowController)
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
}
