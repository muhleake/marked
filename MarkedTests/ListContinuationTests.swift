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
