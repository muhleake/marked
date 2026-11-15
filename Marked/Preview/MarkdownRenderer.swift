import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// GitHub-flavored Markdown → HTML via Apple's swift-cmark (cmark-gfm).
enum MarkdownRenderer {
    /// GFM extensions. `tagfilter` escapes the raw-HTML tags GitHub disallows
    /// (script, iframe, style, …) while other inline HTML still renders.
    static let extensionNames = ["table", "strikethrough", "tasklist", "autolink", "tagfilter"]

    private static let registerExtensions: Void = cmark_gfm_core_extensions_ensure_registered()

    /// - Parameters:
    ///   - sourcePositions: adds `data-sourcepos="line:col-line:col"` to block
    ///     elements, used for editor → preview scroll sync.
    ///   - hidingFrontMatter: leaves out a front matter block at the top. Off for text
    ///     that doesn't start at the top of the file, such as a selection.
    static func html(from markdown: String, sourcePositions: Bool = true, hidingFrontMatter: Bool = true) -> String {
        _ = registerExtensions

        var options = CMARK_OPT_UNSAFE | CMARK_OPT_FOOTNOTES | CMARK_OPT_STRIKETHROUGH_DOUBLE_TILDE
        if sourcePositions { options |= CMARK_OPT_SOURCEPOS }

        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }

        for name in extensionNames {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        var source = hidingFrontMatter ? blankingFrontMatter(in: markdown) : markdown
        source.withUTF8 { buffer in
            buffer.withMemoryRebound(to: CChar.self) { chars in
                if let base = chars.baseAddress { cmark_parser_feed(parser, base, chars.count) }
            }
        }

        guard let document = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(document) }

        guard let html = cmark_render_html(document, options, cmark_parser_get_syntax_extensions(parser)) else { return "" }
        defer { free(html) }
        return String(cString: html)
    }

    /// Replaces a front matter block with empty lines, so it isn't rendered and later
    /// lines keep their line numbers. Front matter is metadata that site generators and
    /// notes apps put at the very top: YAML between `---` and `---` (or `...`), or TOML
    /// between `+++` lines. Without a closing line, nothing is hidden.
    static func blankingFrontMatter(in markdown: String) -> String {
        guard markdown.hasPrefix("---") || markdown.hasPrefix("+++") else { return markdown }
        let fences: [Substring: Set<Substring>] = ["---": ["---", "..."], "+++": ["+++"]]
        // Split on UTF-16 so "\r\n" (one Character in Swift) still breaks lines.
        var lines = (markdown as NSString).components(separatedBy: "\n")
        func trimmed(_ line: String) -> Substring {
            var line = line[...]
            while let last = line.unicodeScalars.last, " \t\r".unicodeScalars.contains(last) {
                line = line.dropLast()
            }
            return line
        }
        guard lines.count > 1, let closers = fences[trimmed(lines[0])],
              let end = lines.indices.dropFirst().first(where: { closers.contains(trimmed(lines[$0])) })
        else { return markdown }
        for index in 0...end { lines[index] = "" }
        return lines.joined(separator: "\n")
    }
}
