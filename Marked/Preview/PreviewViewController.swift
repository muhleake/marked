import AppKit
import WebKit

/// The right-hand pane: a WKWebView showing the rendered document.
///
/// The page (preview.html + preview.css) loads once. Edits re-render off the main
/// thread and swap the article's contents through `update(html, base)`, so the
/// scroll position holds. That function and scroll sync live in an isolated
/// content world; the page itself runs no script (see the CSP in preview.html).
final class PreviewViewController: NSViewController, WKNavigationDelegate {
    static let debounceInterval: TimeInterval = 0.15

    private weak var document: MarkdownDocument?
    private(set) var webView: WKWebView!

    private static let renderQueue = DispatchQueue(label: "io.github.muhleake.marked.render", qos: .userInitiated)
    private var pendingRender: DispatchWorkItem?
    private var renderGeneration = 0
    private var pageLoaded = false
    private var rulesInstalled = false
    private var queuedUpdate: (html: String, base: String)?
    private var queuedScroll: Double?
    private var needsRenderWhenShown = true

    /// When false (pane collapsed), edits only mark the preview stale.
    var isActive = true {
        didSet {
            if isActive && !oldValue && needsRenderWhenShown { renderNow() }
        }
    }

    /// Called after each completed render with the time cmark took. Used by tests.
    var onRender: ((TimeInterval) -> Void)?

    /// Opens clicked links. Replaceable so tests don't launch a browser.
    var openExternally: (URL) -> Void = { NSWorkspace.shared.open($0) }

    init(document: MarkdownDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(storageDidProcessEditing(_:)),
            name: NSTextStorage.didProcessEditingNotification, object: document.textStorage)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        NotificationCenter.default.removeObserver(self)
        pendingRender?.cancel()
    }

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.suppressesIncrementalRendering = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.isolatedScript, injectionTime: .atDocumentEnd,
            forMainFrameOnly: true, in: .defaultClient))

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 600), configuration: configuration)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.setAccessibilityLabel("Preview")
        self.webView = webView
        view = webView

        ContentRules.load { [weak self] rules in
            guard let self else { return }
            if let rules { self.webView.configuration.userContentController.add(rules) }
            self.rulesInstalled = true
            self.loadShell()
        }
    }

    private func loadShell() {
        guard let shell = Bundle.main.url(forResource: "preview", withExtension: "html") else { return }
        // Read access to "/" lets relative images anywhere on disk load (the app is unsandboxed).
        webView.loadFileURL(shell, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    // MARK: - Rendering

    @objc private func storageDidProcessEditing(_ note: Notification) {
        guard let storage = note.object as? NSTextStorage, storage.editedMask.contains(.editedCharacters) else { return }
        scheduleRender()
    }

    func scheduleRender() {
        pendingRender?.cancel()
        guard isActive else { needsRenderWhenShown = true; return }
        let item = DispatchWorkItem { [weak self] in self?.renderNow() }
        pendingRender = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceInterval, execute: item)
    }

    func renderNow() {
        pendingRender?.cancel()
        pendingRender = nil
        guard let document else { return }
        needsRenderWhenShown = false
        renderGeneration += 1
        let generation = renderGeneration
        let text = document.text
        let base = (document.fileURL?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser)
            .absoluteString

        Self.renderQueue.async { [weak self] in
            let start = CFAbsoluteTimeGetCurrent()
            let html = MarkdownRenderer.html(from: text)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            DispatchQueue.main.async {
                guard let self, generation == self.renderGeneration else { return }
                self.apply(html: html, base: base)
                self.onRender?(elapsed)
            }
        }
    }

    private func apply(html: String, base: String) {
        guard pageLoaded else { queuedUpdate = (html, base); return }
        webView.callAsyncJavaScript(
            "marked.update(html, base)", arguments: ["html": html, "base": base],
            in: nil, in: .defaultClient, completionHandler: nil)
    }

    /// Runs JavaScript in Marked's isolated world (where `marked.*` is defined).
    func evaluate(_ body: String, arguments: [String: Any] = [:]) async throws -> Any? {
        try await webView.callAsyncJavaScript(body, arguments: arguments, contentWorld: .defaultClient)
    }

    // MARK: - Scroll sync

    /// Scrolls so the element rendered from (fractional, 1-based) source `line` is at the top.
    func scrollToSourceLine(_ line: Double) {
        guard pageLoaded else { queuedScroll = line; return }
        webView.callAsyncJavaScript(
            "marked.scrollToLine(line)", arguments: ["line": line],
            in: nil, in: .defaultClient, completionHandler: nil)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoaded = true
        if let queuedUpdate {
            self.queuedUpdate = nil
            apply(html: queuedUpdate.html, base: queuedUpdate.base)
        } else if isActive && needsRenderWhenShown {
            renderNow()
        }
        if let queuedScroll {
            self.queuedScroll = nil
            scrollToSourceLine(queuedScroll)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(policy(for: navigationAction.request.url, type: navigationAction.navigationType,
                               isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true))
    }

    /// The preview never navigates: only the initial shell load is allowed; clicked
    /// links open in the default browser (or app, for local files).
    func policy(for url: URL?, type: WKNavigationType, isMainFrame: Bool) -> WKNavigationActionPolicy {
        guard let url else { return .cancel }
        let shell = Bundle.main.url(forResource: "preview", withExtension: "html")

        if type == .linkActivated {
            // In-page anchors (#heading) scroll within the preview.
            if let shell, url.fragment != nil, url.withoutFragment == shell.withoutFragment { return .allow }
            openExternally(url)
            return .cancel
        }
        if !pageLoaded, isMainFrame, let shell, url.withoutFragment == shell.withoutFragment { return .allow }
        return .cancel
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        pageLoaded = false
        needsRenderWhenShown = true
        loadShell()
    }

    // MARK: - Isolated-world script

    private static let isolatedScript = #"""
    (() => {
      const article = () => document.getElementById('content');
      const sourceStart = el => parseInt(el.getAttribute('data-sourcepos'), 10);

      // Resolve relative src/href against the document's folder. Parsing into a
      // <template> first keeps images from loading against the wrong base.
      function resolve(root, base) {
        for (const el of root.querySelectorAll('img[src], video[src], audio[src], source[src]')) {
          const src = el.getAttribute('src');
          try { el.setAttribute('src', new URL(src, base).href); } catch (e) {}
        }
        for (const a of root.querySelectorAll('a[href]')) {
          const href = a.getAttribute('href');
          if (href.startsWith('#')) continue;
          try { a.setAttribute('href', new URL(href, base).href); } catch (e) {}
        }
      }

      window.marked = {
        update(html, base) {
          const template = document.createElement('template');
          template.innerHTML = html;
          resolve(template.content, base);
          article().replaceChildren(template.content);
        },

        scrollToLine(line) {
          const blocks = Array.from(article().querySelectorAll('[data-sourcepos]'))
            .filter(el => el.parentElement === article() || el.matches('li, tr'));
          if (line <= 1 || blocks.length === 0) { window.scrollTo(0, 0); return; }
          let before = null, after = null;
          for (const el of blocks) {
            const start = sourceStart(el);
            if (start <= line) before = el;
            else { after = el; break; }
          }
          const top = el => el.getBoundingClientRect().top + window.scrollY;
          let y;
          if (!before) {
            y = 0;
          } else if (!after) {
            const startTop = top(before);
            const end = parseInt(before.getAttribute('data-sourcepos').split('-')[1], 10) || sourceStart(before);
            const span = Math.max(1, end - sourceStart(before) + 1);
            y = startTop + before.offsetHeight * Math.min(1, (line - sourceStart(before)) / span);
          } else {
            const a = sourceStart(before), b = sourceStart(after);
            y = top(before) + (top(after) - top(before)) * ((line - a) / Math.max(1, b - a));
          }
          window.scrollTo(0, Math.max(0, y - 8));
        },
      };
    })();
    """#
}

/// Blocks every load that isn't a local file (or about:/data:), so the preview
/// never touches the network.
enum ContentRules {
    private static var cached: WKContentRuleList?
    private static var waiting: [(WKContentRuleList?) -> Void] = []
    private static var compiling = false

    static let json = """
    [
      {"trigger": {"url-filter": ".*"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^file:"}, "action": {"type": "ignore-previous-rules"}},
      {"trigger": {"url-filter": "^about:"}, "action": {"type": "ignore-previous-rules"}},
      {"trigger": {"url-filter": "^data:"}, "action": {"type": "ignore-previous-rules"}}
    ]
    """

    static func load(_ completion: @escaping (WKContentRuleList?) -> Void) {
        if let cached { completion(cached); return }
        waiting.append(completion)
        guard !compiling else { return }
        compiling = true
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "MarkedLocalOnly", encodedContentRuleList: json
        ) { list, error in
            if let error { NSLog("Marked: content rules failed to compile: \(error)") }
            cached = list
            compiling = false
            let callbacks = waiting
            waiting.removeAll()
            callbacks.forEach { $0(list) }
        }
    }
}

extension URL {
    var withoutFragment: URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.fragment = nil
        return components.url ?? self
    }
}
