import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// GitHub-flavored Markdown → HTML via Apple's swift-cmark (cmark-gfm).
enum MarkdownRenderer {
    /// GFM extensions. `tagfilter` escapes the raw-HTML tags GitHub disallows
    /// (script, iframe, style, …) while other inline HTML still renders.
    static let extensionNames = ["table", "strikethrough", "tasklist", "autolink", "tagfilter"]

    private static let registerExtensions: Void = cmark_gfm_core_extensions_ensure_registered()

    /// - Parameter sourcePositions: adds `data-sourcepos="line:col-line:col"` to block
    ///   elements, used for editor → preview scroll sync.
    static func html(from markdown: String, sourcePositions: Bool = true) -> String {
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

        var source = markdown
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
}
