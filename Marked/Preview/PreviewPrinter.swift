import AppKit
import WebKit

/// Prints / exports the *rendered* document. It loads the same preview page into
/// an offscreen WKWebView (independent of whether the preview pane is visible),
/// waits for images, then hands back a paginated NSPrintOperation.
final class PreviewPrinter: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let html: String
    private let base: String
    private var completion: ((WKWebView?) -> Void)?
    private var keepAlive: PreviewPrinter?

    private init(html: String, base: String, width: CGFloat) {
        self.html = html
        self.base = base
        webView = PreviewViewController.makeWebView(frame: NSRect(x: 0, y: 0, width: width, height: 1000))
        // Paper is white: print with the light palette regardless of the system theme.
        webView.appearance = NSAppearance(named: .aqua)
        super.init()
        webView.navigationDelegate = self
    }

    /// The HTML to print: rendered Markdown, or the raw text for plain-text windows.
    static func html(for document: MarkdownDocument, markdown: Bool) -> String {
        if markdown { return MarkdownRenderer.html(from: document.text, sourcePositions: false) }
        let escaped = document.text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return "<pre class=\"plain-text\">\(escaped)</pre>"
    }

    /// Builds a print operation for `document` once the offscreen page is ready.
    static func makePrintOperation(for document: MarkdownDocument, markdown: Bool, printInfo: NSPrintInfo,
                                   completion: @escaping (NSPrintOperation?) -> Void) {
        let width = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let base = (document.fileURL?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser).absoluteString
        let printer = PreviewPrinter(html: html(for: document, markdown: markdown), base: base, width: max(width, 200))
        printer.keepAlive = printer
        printer.load { webView in
            defer { printer.keepAlive = nil }
            guard let webView else { completion(nil); return }
            let operation = webView.printOperation(with: printInfo)
            operation.jobTitle = document.displayName
            // WKWebView's print view needs a real frame or it prints blank pages.
            operation.view?.frame = webView.bounds
            completion(operation)
        }
    }

    private func load(_ completion: @escaping (WKWebView?) -> Void) {
        self.completion = completion
        ContentRules.load { [self] rules in
            if let rules { webView.configuration.userContentController.add(rules) }
            guard let shell = PreviewViewController.shellURL else { finish(nil); return }
            webView.loadFileURL(shell, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let script = """
            marked.update(html, base);
            await Promise.all(Array.from(document.images).map(img => img.complete ? null :
                new Promise(resolve => { img.onload = img.onerror = resolve; })));
            return document.body.scrollHeight;
            """
        webView.callAsyncJavaScript(script, arguments: ["html": html, "base": base], in: nil, in: .defaultClient) { [self] result in
            if case .success(let height as Double) = result {
                webView.frame.size.height = max(webView.frame.height, CGFloat(height))
            }
            finish(webView)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(nil) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(nil) }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let isShell = navigationAction.request.url?.withoutFragment == PreviewViewController.shellURL?.withoutFragment
        decisionHandler(isShell && navigationAction.navigationType != .linkActivated ? .allow : .cancel)
    }

    private func finish(_ webView: WKWebView?) {
        let completion = completion
        self.completion = nil
        completion?(webView)
    }
}
