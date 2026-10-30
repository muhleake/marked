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

    func testTintLandsInTheRightPlaceFarIntoTheDocument() {
        let (s, h) = highlighted("😀 emoji first\n\nplain\n\nlast line")
        let at = (s.string as NSString).range(of: "plain").location
        s.replaceCharacters(in: NSRange(location: at, length: 5), with: "**bold** `code`")
        let bold = (s.string as NSString).range(of: "bold").location
        let code = (s.string as NSString).range(of: "code").location
        XCTAssertTrue(isBold(s, at: bold))
        XCTAssertFalse(isBold(s, at: bold - 3), "the blank line before it stays plain")
        XCTAssertEqual(color(s, at: code), MarkdownHighlighter.Palette.code)
        XCTAssertEqual(color(s, at: s.length - 1), .textColor)
        _ = h
    }

    /// The incremental fence list must always match a full scan.
    func testFenceTrackingMatchesFullScanThroughEdits() {
        let (s, h) = highlighted("intro\n```\ncode\n```\ntext\n~~~\nmore\n~~~\nend")
        var generator = SystemRandomNumberGenerator()
        let snippets = ["x", "\n", "```\n", "\n```", "~~~\n", "  ```swift\n", "`", "- item\n", "😀"]
        for step in 0..<400 {
            let length = s.length
            let location = Int.random(in: 0...length, using: &generator)
            let removal = step % 3 == 0 ? Int.random(in: 0...min(12, length - location), using: &generator) : 0
            let insertion = step % 3 == 2 ? "" : snippets.randomElement(using: &generator)!
            let safe = (s.string as NSString).rangeOfComposedCharacterSequences(for: NSRange(location: location, length: removal))
            s.replaceCharacters(in: safe, with: insertion)
            XCTAssertEqual(h.fenceLineStarts, MarkdownHighlighter.fenceLineStarts(in: s.string as NSString), "step \(step)")
        }
    }

    func testReturnInMidLineTintsTheNewLine() {
        let (s, h) = highlighted("text# Heading")
        s.replaceCharacters(in: NSRange(location: 4, length: 0), with: "\n")
        XCTAssertEqual(color(s, at: 8), MarkdownHighlighter.Palette.heading)
        XCTAssertTrue(isBold(s, at: 8))
        _ = h
    }

    func testTypingOnTheLineAboveAClosingFenceStaysCode() {
        let (s, h) = highlighted("```\nabc\n```\n# after")
        s.replaceCharacters(in: NSRange(location: 7, length: 0), with: "d")
        XCTAssertEqual(color(s, at: 5), MarkdownHighlighter.Palette.code)
        let after = (s.string as NSString).range(of: "after").location
        XCTAssertEqual(color(s, at: after), MarkdownHighlighter.Palette.heading)
        _ = h
    }

    func testAddingAMatchedPairOfFencesTintsBetweenThem() {
        let (s, h) = highlighted("# one\n# two\n# three")
        s.replaceCharacters(in: NSRange(location: 0, length: 0), with: "```\nx\n```\n")
        let one = (s.string as NSString).range(of: "one").location
        XCTAssertEqual(color(s, at: 4), MarkdownHighlighter.Palette.code)
        XCTAssertEqual(color(s, at: one), MarkdownHighlighter.Palette.heading)
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
