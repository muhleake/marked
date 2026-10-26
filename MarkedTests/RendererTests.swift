import XCTest
@testable import Marked

final class RendererTests: XCTestCase {
    private func html(_ markdown: String) -> String {
        MarkdownRenderer.html(from: markdown, sourcePositions: false)
    }

    func testHeadings() {
        XCTAssertEqual(html("# One"), "<h1>One</h1>\n")
        XCTAssertEqual(html("###### Six"), "<h6>Six</h6>\n")
        XCTAssertEqual(html("Setext\n==="), "<h1>Setext</h1>\n")
    }

    func testEmphasis() {
        XCTAssertEqual(html("**bold** *italic* `code`"), "<p><strong>bold</strong> <em>italic</em> <code>code</code></p>\n")
    }

    func testStrikethrough() {
        XCTAssertEqual(html("~~gone~~"), "<p><del>gone</del></p>\n")
        // Double tilde only, like GitHub.
        XCTAssertEqual(html("~single~"), "<p>~single~</p>\n")
    }

    func testTable() {
        let out = html("| a | b |\n|:--|--:|\n| 1 | 2 |")
        XCTAssertTrue(out.contains("<table>"), out)
        XCTAssertTrue(out.contains("<th align=\"left\">a</th>"), out)
        XCTAssertTrue(out.contains("<td align=\"right\">2</td>"), out)
    }

    func testTaskList() {
        let out = html("- [ ] todo\n- [x] done")
        XCTAssertTrue(out.contains("<input type=\"checkbox\" disabled=\"\" /> todo"), out)
        XCTAssertTrue(out.contains("<input type=\"checkbox\" checked=\"\" disabled=\"\" /> done"), out)
    }

    func testAutolink() {
        XCTAssertTrue(html("see www.example.com").contains("<a href=\"http://www.example.com\">www.example.com</a>"))
        XCTAssertTrue(html("https://apple.com/x").contains("<a href=\"https://apple.com/x\">"))
        XCTAssertTrue(html("mail me@example.com").contains("<a href=\"mailto:me@example.com\">"))
    }

    func testFencedCode() {
        let out = html("```swift\nlet x = 1 < 2\n```")
        XCTAssertEqual(out, "<pre><code class=\"language-swift\">let x = 1 &lt; 2\n</code></pre>\n")
    }

    func testBlockquoteListsRuleLinkImage() {
        XCTAssertTrue(html("> quote").contains("<blockquote>"))
        XCTAssertTrue(html("1. one\n2. two").contains("<ol>"))
        XCTAssertTrue(html("- a\n- b").contains("<ul>"))
        XCTAssertEqual(html("---"), "<hr />\n")
        XCTAssertEqual(html("[t](https://x.dev)"), "<p><a href=\"https://x.dev\">t</a></p>\n")
        XCTAssertEqual(html("![alt](img/pic.png)"), "<p><img src=\"img/pic.png\" alt=\"alt\" /></p>\n")
    }

    func testFootnotes() {
        let out = html("Text[^1]\n\n[^1]: Note")
        XCTAssertTrue(out.contains("footnotes"), out)
    }

    func testDangerousTagsFilteredButInlineHTMLKept() {
        XCTAssertTrue(html("<script>alert(1)</script>").contains("&lt;script>"))
        XCTAssertTrue(html("<iframe src=x></iframe>").contains("&lt;iframe"))
        XCTAssertTrue(html("a<br>b <kbd>⌘</kbd>").contains("<kbd>⌘</kbd>"))
    }

    func testSourcePositions() {
        let out = MarkdownRenderer.html(from: "# A\n\npara\n\n- x\n- y")
        XCTAssertTrue(out.contains("<h1 data-sourcepos=\"1:1-1:3\">"), out)
        XCTAssertTrue(out.contains("<p data-sourcepos=\"3:1-3:4\">"), out)
        XCTAssertTrue(out.contains("<li data-sourcepos=\"6:1-6:3\">"), out)
    }

    func testUnicode() {
        XCTAssertEqual(html("Ünïcödé ✓ 日本語 🎉"), "<p>Ünïcödé ✓ 日本語 🎉</p>\n")
    }

    func testEmpty() {
        XCTAssertEqual(html(""), "")
    }

    /// Typing latency budget: a 5,000-line document must render well under the 150 ms debounce.
    func testFiveThousandLineRenderTime() {
        let doc = Self.largeDocument(lines: 5000)
        _ = MarkdownRenderer.html(from: doc)  // warm up
        var times: [Double] = []
        for _ in 0..<5 {
            let start = CFAbsoluteTimeGetCurrent()
            _ = MarkdownRenderer.html(from: doc)
            times.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
        }
        let median = times.sorted()[times.count / 2]
        print(String(format: "RENDER-5000: median %.1f ms (runs: %@)", median, times.map { String(format: "%.1f", $0) }.joined(separator: ", ")))
        XCTAssertLessThan(median, 100)
    }

    static func largeDocument(lines: Int) -> String {
        let block = [
            "## Section heading", "",
            "A paragraph with **bold**, *italic*, `code`, ~~strike~~ and a [link](https://example.com).",
            "Another line of the same paragraph that wraps a little in the editor window.", "",
            "- bullet one", "- bullet two", "- [ ] a task", "- [x] a done task", "",
            "| col | col |", "|-----|-----|", "| a   | b   |", "",
            "```swift", "let answer = 42", "```", "",
            "> a quote", "",
        ]
        var out: [String] = []
        out.reserveCapacity(lines)
        while out.count < lines { out.append(contentsOf: block) }
        return out.prefix(lines).joined(separator: "\n")
    }
}
