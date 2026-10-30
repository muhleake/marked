import AppKit
import XCTest
@testable import Marked

final class TextCountsTests: XCTestCase {
    func testCounts() {
        XCTAssertEqual(TextCounts(""), TextCounts(words: 0, characters: 0, lines: 0))
        XCTAssertEqual(TextCounts("one two\nthree"), TextCounts(words: 3, characters: 13, lines: 2))
        XCTAssertEqual(TextCounts("# Title\n\n- item 👍🏽"), TextCounts(words: 2, characters: 17, lines: 3), "an emoji is one character and not a word")
        XCTAssertEqual(TextCounts(words: 1, characters: 1200, lines: 1).description, "1 word · 1,200 characters · 1 line")
    }
}
