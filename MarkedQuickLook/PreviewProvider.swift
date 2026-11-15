import Foundation
import QuickLookUI
import UniformTypeIdentifiers

/// Finder's Quick Look preview (Space) for Markdown files. Renders with Marked's own
/// renderer and stylesheet into a static page. It runs only while a preview is open.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let data = try Data(contentsOf: request.fileURL, options: .mappedIfSafe)
        let text = try FileEncoding.decode(data).text
        let page = Self.page(body: MarkdownRenderer.html(from: text, sourcePositions: false),
                             title: request.fileURL.lastPathComponent)
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 900, height: 1000)) { _ in
            Data(page.utf8)
        }
    }

    private static let stylesheet: String = {
        guard let url = Bundle(for: PreviewProvider.self).url(forResource: "preview", withExtension: "css") else { return "" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    /// A standalone page. The policy allows only the inline stylesheet and embedded
    /// images, so a preview never loads anything from the network or runs script.
    static func page(body: String, title: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:">
        <meta name="color-scheme" content="light dark">
        <title>\(escaped(title))</title>
        <style>\(stylesheet)</style>
        </head>
        <body>
        <article class="markdown-body">\(body)</article>
        </body>
        </html>
        """
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
