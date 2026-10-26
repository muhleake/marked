import AppKit
import XCTest
@testable import Marked

/// Notation as in MarkdownCommandsTests: `‸` cursor, `«…»` selection.
final class ListContinuationTests: XCTestCase {
    private func parse(_ marked: String) -> (String, NSRange) {
        var s = marked as NSString
        if s.range(of: "‸").location != NSNotFound {
            let at = s.range(of: "‸").location
            return (s.replacingCharacters(in: NSRange(location: at, length: 1), with: ""), NSRange(location: at, length: 0))
        }
        let open = s.range(of: "«").location
        s = s.replacingCharacters(in: NSRange(location: open, length: 1), with: "") as NSString
        let close = s.range(of: "»").location
        s = s.replacingCharacters(in: NSRange(location: close, length: 1), with: "") as NSString
        return (s as String, NSRange(location: open, length: close - open))
    }

    private func format(_ text: String, _ sel: NSRange) -> String {
        let s = text as NSString
        if sel.length == 0 { return s.replacingCharacters(in: NSRange(location: sel.location, length: 0), with: "‸") }
        let closed = s.replacingCharacters(in: NSRange(location: NSMaxRange(sel), length: 0), with: "»") as NSString
        return closed.replacingCharacters(in: NSRange(location: sel.location, length: 0), with: "«")
    }

    private func enter(_ input: String) -> String? {
        let (text, sel) = parse(input)
        guard let edit = ListContinuation.newline(in: text, selection: sel) else { return nil }
        return format(edit.applied(to: text), edit.selection)
    }

    private func tab(_ input: String, outdent: Bool = false) -> String? {
        let (text, sel) = parse(input)
        guard let edit = ListContinuation.indent(in: text, selection: sel, outdent: outdent) else { return nil }
        return format(edit.applied(to: text), edit.selection)
    }

    func testBulletContinues() { XCTAssertEqual(enter("- one‸"), "- one\n- ‸") }
    func testStarAndPlusContinue() {
        XCTAssertEqual(enter("* one‸"), "* one\n* ‸")
        XCTAssertEqual(enter("+ one‸"), "+ one\n+ ‸")
    }
    func testNumberedIncrements() { XCTAssertEqual(enter("1. one‸"), "1. one\n2. ‸") }
    func testNumberedKeepsDelimiterAndLargeNumbers() {
        XCTAssertEqual(enter("9) nine‸"), "9) nine\n10) ‸")
        XCTAssertEqual(enter("99. x‸"), "99. x\n100. ‸")
    }
    func testTaskContinuesUnchecked() {
        XCTAssertEqual(enter("- [ ] a‸"), "- [ ] a\n- [ ] ‸")
        XCTAssertEqual(enter("- [x] done‸"), "- [x] done\n- [ ] ‸")
    }
    func testIndentPreserved() { XCTAssertEqual(enter("    - nested‸"), "    - nested\n    - ‸") }
    func testEmptyItemEndsList() {
        XCTAssertEqual(enter("- a\n- ‸"), "- a\n‸")
        XCTAssertEqual(enter("1. a\n2. ‸"), "1. a\n‸")
        XCTAssertEqual(enter("- [ ] ‸"), "‸")
        XCTAssertEqual(enter("  -   ‸"), "‸")
    }
    func testSplitsItemAtCursor() { XCTAssertEqual(enter("- hello‸world"), "- hello\n- ‸world") }
    func testMiddleOfList() { XCTAssertEqual(enter("1. a‸\n2. b"), "1. a\n2. ‸\n2. b") }
    func testNotAList() {
        XCTAssertNil(enter("plain‸"))
        XCTAssertNil(enter("-not a list‸"))
        XCTAssertNil(enter("1.5 is a number‸"))
    }
    func testCursorBeforeMarkerIsNormalReturn() { XCTAssertNil(enter("‸- item")); XCTAssertNil(enter("-‸ item")) }
    func testSelectionIsNormalReturn() { XCTAssertNil(enter("- «item»")) }
    func testInsideFencedCodeIsNormalReturn() { XCTAssertNil(enter("```\n- not a list‸\n```")) }
    func testAfterFenceClosesContinues() { XCTAssertEqual(enter("```\nx\n```\n- a‸"), "```\nx\n```\n- a\n- ‸") }

    func testTabIndentsListItem() { XCTAssertEqual(tab("- it‸em"), "    - it‸em") }
    func testTabOnPlainLineIsNormalTab() { XCTAssertNil(tab("plain‸")) }
    func testTabIndentsSelectedLines() { XCTAssertEqual(tab("«a\nb»"), "«    a\n    b»") }
    func testTabSkipsBlankLinesInSelection() { XCTAssertEqual(tab("«a\n\nb»"), "«    a\n\n    b»") }
    func testShiftTabOutdents() {
        XCTAssertEqual(tab("    - it‸em", outdent: true), "- it‸em")
        XCTAssertEqual(tab("\t- x‸", outdent: true), "- x‸")
        XCTAssertEqual(tab("  - x‸", outdent: true), "- x‸")
        XCTAssertEqual(tab("«    a\n      b»", outdent: true), "«a\n  b»")
    }
    func testShiftTabAtMarginDoesNothing() { XCTAssertNil(tab("- x‸", outdent: true)) }
}

final class HighlighterTests: XCTestCase {
    private func highlighted(_ text: String, enabled: Bool = true) -> (NSTextStorage, MarkdownHighlighter) {
        let storage = NSTextStorage(string: text)
        let highlighter = MarkdownHighlighter(textStorage: storage, enabled: enabled)
        return (storage, highlighter)
    }

    private func color(_ storage: NSTextStorage, at index: Int) -> NSColor? {
        storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    private func isBold(_ storage: NSTextStorage, at index: Int) -> Bool {
        (storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
    }

    private func isItalic(_ storage: NSTextStorage, at index: Int) -> Bool {
        (storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
    }

    func testHeading() {
        let (s, h) = highlighted("# Title\nbody")
        XCTAssertEqual(color(s, at: 0), MarkdownHighlighter.Palette.marker)
        XCTAssertEqual(color(s, at: 3), MarkdownHighlighter.Palette.heading)
        XCTAssertTrue(isBold(s, at: 3))
        XCTAssertEqual(color(s, at: 9), .textColor)
        XCTAssertFalse(isBold(s, at: 9))
        _ = h
    }

    func testEmphasisAndMarkersStayVisible() {
        let text = "a **bold** and *it* x"
        let (s, h) = highlighted(text)
        XCTAssertTrue(isBold(s, at: 5))
        XCTAssertEqual(color(s, at: 2), MarkdownHighlighter.Palette.marker)
        XCTAssertTrue(isItalic(s, at: 16))
        XCTAssertEqual(s.string, text, "characters are never hidden or changed")
        _ = h
    }

    func testInlineCodeLinksListsQuotes() {
        let (s, h) = highlighted("- item `code` [t](u)\n> quote\n1. num")
        XCTAssertEqual(color(s, at: 0), MarkdownHighlighter.Palette.listMarker)
        XCTAssertEqual(color(s, at: 8), MarkdownHighlighter.Palette.code)
        XCTAssertEqual(color(s, at: 15), MarkdownHighlighter.Palette.link)
        XCTAssertEqual(color(s, at: 18), MarkdownHighlighter.Palette.url)
        XCTAssertEqual(color(s, at: 21), MarkdownHighlighter.Palette.quoteMarker)
        XCTAssertEqual(color(s, at: 24), MarkdownHighlighter.Palette.quote)
        XCTAssertEqual(color(s, at: 29), MarkdownHighlighter.Palette.listMarker)
        _ = h
    }

    func testFencedBlockAndReactsToFenceEdits() {
        let (s, h) = highlighted("```\n# not heading\n```\n# heading")
        XCTAssertEqual(color(s, at: 6), MarkdownHighlighter.Palette.code)
        XCTAssertFalse(isBold(s, at: 6))
        XCTAssertEqual(color(s, at: 24), MarkdownHighlighter.Palette.heading)

        // Delete the opening fence: the rest is no longer code.
        s.replaceCharacters(in: NSRange(location: 0, length: 4), with: "")
        XCTAssertEqual(color(s, at: 2), MarkdownHighlighter.Palette.heading)
        // Typing a fence at the top turns what follows into code.
        s.replaceCharacters(in: NSRange(location: 0, length: 0), with: "```\n")
        XCTAssertEqual(color(s, at: 6), MarkdownHighlighter.Palette.code)
        _ = h
    }

    func testIncrementalEditOnlyRetintsParagraph() {
        let (s, h) = highlighted("plain\n# Head")
        s.replaceCharacters(in: NSRange(location: 0, length: 0), with: "# ")
        XCTAssertEqual(color(s, at: 3), MarkdownHighlighter.Palette.heading)
        XCTAssertEqual(color(s, at: 10), MarkdownHighlighter.Palette.heading)
        _ = h
    }

    func testDisabledIsPlain() {
        let (s, h) = highlighted("# Title **b**", enabled: false)
        XCTAssertEqual(color(s, at: 3), .textColor)
        XCTAssertFalse(isBold(s, at: 3))
        h.isEnabled = true
        XCTAssertTrue(isBold(s, at: 3))
        h.isEnabled = false
        XCTAssertFalse(isBold(s, at: 3))
    }

    func testFiveThousandLineFullAndIncrementalTiming() {
        let storage = NSTextStorage(string: RendererTests.largeDocument(lines: 5000))
        var start = CFAbsoluteTimeGetCurrent()
        let h = MarkdownHighlighter(textStorage: storage, enabled: true)
        let full = (CFAbsoluteTimeGetCurrent() - start) * 1000
        start = CFAbsoluteTimeGetCurrent()
        storage.replaceCharacters(in: NSRange(location: storage.length / 2, length: 0), with: "x")
        let incremental = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print(String(format: "HIGHLIGHT-5000: full %.1f ms, one keystroke %.2f ms", full, incremental))
        XCTAssertLessThan(incremental, 8, "a keystroke must re-tint in well under a frame")
        _ = h
    }
}

final class CountsTests: XCTestCase {
    func testCounts() {
        XCTAssertEqual(TextCounts(""), TextCounts(words: 0, characters: 0, lines: 0))
        XCTAssertEqual(TextCounts("one two\nthree"), TextCounts(words: 3, characters: 13, lines: 2))
        XCTAssertEqual(TextCounts("# Title\n\n- item 👍🏽"), TextCounts(words: 2, characters: 17, lines: 3), "an emoji is one character and not a word")
        XCTAssertEqual(TextCounts(words: 1, characters: 1200, lines: 1).description, "1 word · 1,200 characters · 1 line")
    }
}

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
