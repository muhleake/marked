import AppKit
import XCTest
@testable import Marked

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

    func testInlineHTMLTagsDimmedAndColorShown() {
        let (s, h) = highlighted("a <u>b</u> <span style=\"color: #30a46c\">green</span>")
        XCTAssertEqual(color(s, at: 2), MarkdownHighlighter.Palette.marker)
        XCTAssertEqual(color(s, at: 5), .textColor)
        let green = (s.string as NSString).range(of: "green").location
        XCTAssertEqual(color(s, at: green), NSColor(hexString: "#30a46c"))
        XCTAssertEqual(color(s, at: green - 1), MarkdownHighlighter.Palette.marker)
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
