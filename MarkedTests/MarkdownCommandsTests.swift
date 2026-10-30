import AppKit
import XCTest
@testable import Marked

/// Notation: `‸` is the cursor, `«…»` the selection.
final class MarkdownCommandsTests: XCTestCase {
    typealias Command = (String, NSRange) -> MarkdownEdit

    private func parse(_ marked: String) -> (String, NSRange) {
        var s = marked as NSString
        if s.range(of: "‸").location != NSNotFound {
            let at = s.range(of: "‸").location
            s = s.replacingCharacters(in: NSRange(location: at, length: 1), with: "") as NSString
            return (s as String, NSRange(location: at, length: 0))
        }
        let open = s.range(of: "«").location
        precondition(open != NSNotFound, "need ‸ or «…» in \(marked)")
        s = s.replacingCharacters(in: NSRange(location: open, length: 1), with: "") as NSString
        let close = s.range(of: "»").location
        s = s.replacingCharacters(in: NSRange(location: close, length: 1), with: "") as NSString
        return (s as String, NSRange(location: open, length: close - open))
    }

    private func format(_ text: String, _ selection: NSRange) -> String {
        let s = text as NSString
        if selection.length == 0 { return s.replacingCharacters(in: NSRange(location: selection.location, length: 0), with: "‸") }
        let withClose = s.replacingCharacters(in: NSRange(location: NSMaxRange(selection), length: 0), with: "»") as NSString
        return withClose.replacingCharacters(in: NSRange(location: selection.location, length: 0), with: "«")
    }

    private func check(_ input: String, _ expected: String, _ command: Command, file: StaticString = #filePath, line: UInt = #line) {
        let (text, selection) = parse(input)
        let edit = command(text, selection)
        XCTAssertEqual(format(edit.applied(to: text), edit.selection), expected, file: file, line: line)
    }

    /// Applies the command, then again on its own result, and expects the original back.
    private func checkRoundTrip(_ input: String, _ command: Command, file: StaticString = #filePath, line: UInt = #line) {
        let (text, selection) = parse(input)
        let once = command(text, selection)
        let twice = command(once.applied(to: text), once.selection)
        XCTAssertEqual(format(twice.applied(to: once.applied(to: text)), twice.selection), input, file: file, line: line)
    }

    private let bold: Command = { MarkdownCommands.toggleInline(.bold, in: $0, selection: $1) }
    private let italic: Command = { MarkdownCommands.toggleInline(.italic, in: $0, selection: $1) }
    private let strike: Command = { MarkdownCommands.toggleInline(.strikethrough, in: $0, selection: $1) }
    private let code: Command = { MarkdownCommands.toggleInline(.code, in: $0, selection: $1) }
    private func heading(_ n: Int) -> Command { { MarkdownCommands.toggleHeading(level: n, in: $0, selection: $1) } }
    private let bullet: Command = { MarkdownCommands.toggleList(.bullet, in: $0, selection: $1) }
    private let numbered: Command = { MarkdownCommands.toggleList(.numbered, in: $0, selection: $1) }
    private let task: Command = { MarkdownCommands.toggleList(.task, in: $0, selection: $1) }
    private let quote: Command = { MarkdownCommands.toggleQuote(in: $0, selection: $1) }
    private let codeBlock: Command = { MarkdownCommands.toggleCodeBlock(in: $0, selection: $1) }
    private let link: Command = { MarkdownCommands.toggleLink(in: $0, selection: $1) }
    private let image: Command = { MarkdownCommands.toggleImage(in: $0, selection: $1) }
    private let table: Command = { MarkdownCommands.toggleTable(in: $0, selection: $1) }
    private let rule: Command = { MarkdownCommands.toggleHorizontalRule(in: $0, selection: $1) }

    // MARK: - Bold

    func testBoldWrapsSelection() { check("a «word» b", "a **«word»** b", bold) }
    func testBoldUnwrapsWhenMarkersOutsideSelection() { check("a **«word»** b", "a «word» b", bold) }
    func testBoldUnwrapsWhenMarkersInsideSelection() { check("a «**word**» b", "a «word» b", bold) }
    func testBoldEmptySelectionInsertsPair() { check("a ‸ b", "a **‸** b", bold) }
    func testBoldEmptyPairTogglesOff() { check("a **‸** b", "a ‸ b", bold) }
    func testBoldCursorInsideSpanUnwraps() { check("x **bo‸ld** y", "x bo‸ld y", bold) }
    func testBoldCursorInsideSecondSpan() { check("**a** and **b‸c**", "**a** and b‸c", bold) }
    func testBoldBetweenSpansInsertsPair() { check("**a** x‸ **b**", "**a** x**‸** **b**", bold) }
    func testBoldKeepsWhitespaceOutside() { check("a« word »b", "a **«word»** b", bold) }
    func testBoldUnderscoreUnwraps() { check("__«x»__", "«x»", bold) }
    func testBoldMultiLine() { check("«one\ntwo»", "**«one\ntwo»**", bold) }
    func testBoldRoundTrip() { checkRoundTrip("say «hello» now", bold) }

    // MARK: - Italic

    func testItalicWrap() { check("«x»", "*«x»*", italic) }
    func testItalicUnwrap() { check("*«x»*", "«x»", italic) }
    func testItalicOnBoldMakesBoldItalic() { check("**«x»**", "***«x»***", italic) }
    func testItalicOffBoldItalicLeavesBold() { check("***«x»***", "**«x»**", italic) }
    func testBoldOffBoldItalicLeavesItalic() { check("***«x»***", "*«x»*", bold) }
    func testItalicUnderscore() { check("_«x»_", "«x»", italic) }
    func testItalicCursorInside() { check("**b** and *i‸t*", "**b** and i‸t", italic) }
    func testItalicInsideBoldInsertsPair() { check("**b‸old**", "**b*‸*old**", italic) }

    // MARK: - Strikethrough and code

    func testStrikethrough() { check("«x»", "~~«x»~~", strike); check("~~«x»~~", "«x»", strike) }
    func testStrikethroughCursor() { check("‸", "~~‸~~", strike); check("~~a‸b~~", "a‸b", strike) }
    func testInlineCode() { check("«x»", "`«x»`", code); check("`co‸de`", "co‸de", code); check("`«x»`", "«x»", code) }

    // MARK: - Headings

    func testHeadingAdd() { check("Title‸", "# Title‸", heading(1)) }
    func testHeadingToggleOff() { check("# Title‸", "Title‸", heading(1)) }
    func testHeadingReplacesLevel() { check("# Title‸", "## Title‸", heading(2)); check("### T‸", "###### T‸", heading(6)) }
    func testHeadingSixOff() { check("###### T‸", "T‸", heading(6)) }
    func testHeadingEmptyLine() { check("‸", "## ‸", heading(2)) }
    func testHeadingCursorAtLineStart() { check("‸Title", "# ‸Title", heading(1)) }
    func testHeadingMultiLine() { check("«a\nb»", "«### a\n### b»", heading(3)) }
    func testHeadingMixedLevelsUnify() { check("«# a\n## b»", "«## a\n## b»", heading(2)) }
    func testHeadingOnlyTouchesItsLine() { check("one\ntw‸o\nthree", "one\n# tw‸o\nthree", heading(1)) }

    // MARK: - Lists

    func testBulletAdd() { check("«a\nb\nc»", "«- a\n- b\n- c»", bullet) }
    func testBulletRemove() { check("«- a\n- b»", "«a\nb»", bullet) }
    func testBulletRemoveStarMarker() { check("* a‸", "a‸", bullet) }
    func testNumberedAddsIncrementingNumbers() { check("«a\nb\nc»", "«1. a\n2. b\n3. c»", numbered) }
    func testNumberedRemove() { check("«1. a\n2. b»", "«a\nb»", numbered) }
    func testBulletToNumbered() { check("«- a\n- b»", "«1. a\n2. b»", numbered) }
    func testNumberedToBullet() { check("1. one‸", "- one‸", bullet) }
    func testListSkipsBlankLines() { check("«a\n\nb»", "«- a\n\n- b»", bullet) }
    func testListKeepsIndent() { check("  nested‸", "  - nested‸", bullet) }
    func testListCursorAtStart() { check("‸text", "- ‸text", bullet) }
    func testListEmptyLine() { check("‸", "- ‸", bullet) }
    func testListSelectionEndingAtLineStartExcludesThatLine() { check("«a\n»b", "«- a»\nb", bullet) }
    func testTaskAdd() { check("it‸em", "- [ ] it‸em", task) }
    func testTaskFromBullet() { check("- it‸em", "- [ ] it‸em", task) }
    func testTaskRemoveChecked() { check("- [x] done‸", "done‸", task) }
    func testTaskToBullet() { check("- [ ] a‸", "- a‸", bullet) }
    func testListRoundTrip() { checkRoundTrip("«alpha\nbeta»", numbered); checkRoundTrip("«alpha\nbeta»", task) }

    // MARK: - Quote

    func testQuoteAddAndRemove() { check("«a\nb»", "«> a\n> b»", quote); check("«> a\n> b»", "«a\nb»", quote) }
    func testQuoteBlankLineInside() { check("«a\n\nb»", "«> a\n>\n> b»", quote) }
    func testQuoteCursor() { check("> q‸", "q‸", quote); check("q‸", "> q‸", quote) }

    // MARK: - Code block

    func testCodeBlockWrapsLine() { check("«let x»", "```‸\nlet x\n```", codeBlock) }
    func testCodeBlockWrapsLines() { check("«a\nb»", "```‸\na\nb\n```", codeBlock) }
    func testCodeBlockEmptyLine() { check("‸", "```‸\n\n```", codeBlock) }
    func testCodeBlockRemovesFencesAroundCursor() { check("```\nco‸de\n```", "co‸de", codeBlock) }
    func testCodeBlockRemovesFencesAroundSelection() { check("```swift\n«a\nb»\n```", "«a\nb»", codeBlock) }
    func testCodeBlockLeavesOtherBlocksAlone() {
        check("```\nx\n```\nmid‸dle\n```\ny\n```", "```\nx\n```\n```‸\nmiddle\n```\n```\ny\n```", codeBlock)
    }

    // MARK: - Link and image

    func testLinkWrapsSelectionAndSelectsURL() { check("«Apple»", "[Apple](«url»)", link) }
    func testLinkOnSelectedURL() { check("«https://apple.com»", "[«text»](https://apple.com)", link) }
    func testLinkEmpty() { check("‸", "[text](«url»)", link) }
    func testLinkToggleOff() { check("see [Ap‸ple](https://apple.com) now", "see «Apple» now", link) }
    func testLinkSelectedWholeToggleOff() { check("«[a](b)»", "«a»", link) }
    func testLinkRightAfterLinkInsertsNew() { check("[a](b)‸", "[a](b)[text](«url»)", link) }
    func testImageWrap() { check("«diagram»", "![diagram](«path»)", image) }
    func testImageOnPath() { check("«img/x.png»", "![«alt»](img/x.png)", image) }
    func testImageToggleOff() { check("![a‸lt](p.png)", "«alt»", image) }
    func testLinkInsideImageDoesNotUnlinkImage() { check("![a‸](p)", "![a[text](«url»)](p)", link) }

    // MARK: - Table and rule

    private var skeletonSelected: String {
        MarkdownCommands.tableSkeleton.replacingOccurrences(of: "| Column 1 |", with: "| «Column 1» |")
    }

    func testTableOnEmptyDocument() { check("‸", skeletonSelected + "\n", table) }
    func testTableAfterParagraph() { check("Text‸", "Text\n\n" + skeletonSelected + "\n", table) }
    func testTableBeforeParagraph() { check("Text‸\nMore", "Text\n\n" + skeletonSelected + "\n\nMore", table) }
    func testTableToggleRemovesUntouchedSkeleton() {
        let (text, selection) = parse("Text‸")
        let inserted = MarkdownCommands.toggleTable(in: text, selection: selection)
        let afterInsert = inserted.applied(to: text)
        let removed = MarkdownCommands.toggleTable(in: afterInsert, selection: inserted.selection)
        XCTAssertEqual(removed.applied(to: afterInsert), "Text\n\n")
    }
    func testTableNotRemovedOnceEdited() {
        let edited = "| Name | Column 2 | Column 3 |\n| -------- | -------- | -------- |\n|          |          |          |\n|          |          |          |"
        let edit = MarkdownCommands.toggleTable(in: edited, selection: NSRange(location: 3, length: 0))
        XCTAssertTrue(edit.applied(to: edited).hasPrefix(edited), "edited tables are never deleted")
    }

    func testRuleAfterParagraph() { check("Para‸", "Para\n\n---\n‸", rule) }
    func testRuleBetweenParagraphs() { check("Para‸\nNext", "Para\n\n---\n‸\nNext", rule) }
    func testRuleOnEmptyLine() { check("‸", "---\n‸", rule) }
    func testRuleOnBlankLineAfterText() { check("Para\n‸", "Para\n\n---\n‸", rule) }
    func testRuleToggleOff() { check("a\n---‸\nb", "a\n‸b", rule) }

    // MARK: - Unicode safety

    func testEmojiAndCJKOffsets() {
        check("😀 «日本» 😀", "😀 **«日本»** 😀", bold)
        check("👍🏽 it‸em", "- 👍🏽 it‸em", bullet)
    }
}
