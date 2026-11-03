import AppKit
import WebKit

/// The right-hand pane: a WKWebView showing the rendered document.
///
/// The web view (and with it WebKit's page, GPU and network processes) is created
/// only once the preview is first shown, so editor-only and `.txt` windows never
/// pay for it, and it is shut down explicitly when the window closes.
///
/// The page (preview.html + preview.css) loads once. Edits re-render off the main
/// thread and swap the article's contents through `update(html, base)`, so the
/// scroll position holds. That function and scroll sync live in an isolated
/// content world; the page itself runs no script (see the CSP in preview.html).
final class PreviewViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {
    static let debounceInterval: TimeInterval = 0.15
    /// At this pane width, Scale to Window shows the page at its normal size.
    static let scaleReferenceWidth: CGFloat = 640
    private static let scrollMessage = "previewScroll"

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

    /// When false (pane collapsed), edits only mark the preview stale. The first
    /// time it turns true, the web view is created.
    var isActive = false {
        didSet {
            guard isActive, !oldValue else { return }
            makeWebViewIfNeeded()
            if needsRenderWhenShown { renderNow() }
        }
    }

    /// The user scrolled the preview: the (fractional, 1-based) source line now at
    /// its top, or `atDocumentEnd` when scrolled all the way down.
    var onScroll: ((Double) -> Void)?
    static let atDocumentEnd = -1.0

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

    static var shellURL: URL? { Bundle.main.url(forResource: "preview", withExtension: "html") }

    /// A web view set up like the preview: no persistent data, Marked's isolated-world script.
    static func makeWebView(frame: NSRect) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.addUserScript(WKUserScript(
            source: isolatedScript, injectionTime: .atDocumentEnd,
            forMainFrameOnly: true, in: .defaultClient))
        let webView = WKWebView(frame: frame, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        // Pinch to zoom.
        webView.allowsMagnification = true
        return webView
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 600))
        container.setAccessibilityLabel("Preview")
        view = container
        if isActive { makeWebViewIfNeeded() }
    }

    private func makeWebViewIfNeeded() {
        guard webView == nil, isViewLoaded else { return }
        let webView = Self.makeWebView(frame: view.bounds)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.configuration.userContentController.add(
            WeakScriptMessageHandler(self), contentWorld: .defaultClient, name: Self.scrollMessage)
        webView.setAccessibilityLabel("Preview")
        view.addSubview(webView)
        self.webView = webView
        applyTheme()
        applyZoom()
        NotificationCenter.default.addObserver(
            self, selector: #selector(themeDidChange(_:)), name: .previewThemeDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(zoomDidChange(_:)), name: .previewZoomDidChange, object: nil)

        ContentRules.load { [weak self] rules in
            guard let self, let webView = self.webView else { return }
            if let rules { webView.configuration.userContentController.add(rules) }
            self.rulesInstalled = true
            self.loadShell()
        }
    }

    /// Shuts the preview down when its window closes. WebKit keeps a page alive
    /// through its own pending callbacks until it's torn down, and a live web view
    /// holds its window, so without this every closed window stayed in memory.
    func tearDown() {
        pendingRender?.cancel()
        pendingRender = nil
        renderGeneration += 1
        onScroll = nil
        onRender = nil
        NotificationCenter.default.removeObserver(self)
        guard let webView else { return }
        webView.navigationDelegate = nil
        webView.stopLoading()
        let content = webView.configuration.userContentController
        content.removeAllScriptMessageHandlers()
        content.removeAllUserScripts()
        content.removeAllContentRuleLists()
        webView.removeFromSuperview()
        self.webView = nil
        pageLoaded = false
    }

    @objc private func themeDidChange(_ note: Notification) { applyTheme() }

    /// Settings ▸ Preview theme: follow the system, or force light/dark.
    private func applyTheme() {
        webView?.appearance = Preferences.previewTheme.appearance
    }

    // MARK: - Zoom

    @objc private func zoomDidChange(_ note: Notification) { applyZoom() }

    override func viewDidLayout() {
        super.viewDidLayout()
        if Preferences.scalePreviewToWindow { applyZoom() }
    }

    /// `pageZoom` rather than magnification: text re-wraps to fit the pane instead of
    /// running off its edge.
    private func applyZoom() {
        guard let webView else { return }
        var zoom = Preferences.previewZoom
        if Preferences.scalePreviewToWindow, view.bounds.width > 0 {
            zoom *= Double(view.bounds.width / Self.scaleReferenceWidth).clamped(to: 0.5...1.5)
        }
        if abs(webView.pageZoom - zoom) > 0.001 { webView.pageZoom = zoom }
        // Back at 100% also clears any pinch.
        if Preferences.previewZoom == 1, webView.magnification != 1 { webView.magnification = 1 }
    }

    private func loadShell() {
        guard let shell = Self.shellURL, let webView else { return }
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
        guard pageLoaded, let webView else { queuedUpdate = (html, base); return }
        webView.callAsyncJavaScript(
            "marked.update(html, base)", arguments: ["html": html, "base": base],
            in: nil, in: .defaultClient, completionHandler: nil)
    }

    /// Runs JavaScript in Marked's isolated world (where `marked.*` is defined).
    func evaluate(_ body: String, arguments: [String: Any] = [:]) async throws -> Any? {
        guard let webView else { throw CocoaError(.featureUnsupported) }
        return try await webView.callAsyncJavaScript(body, arguments: arguments, contentWorld: .defaultClient)
    }

    // MARK: - Scroll sync

    /// Scrolls so the element rendered from (fractional, 1-based) source `line` is at the top.
    func scrollToSourceLine(_ line: Double) {
        guard pageLoaded, let webView else { queuedScroll = line; return }
        webView.callAsyncJavaScript(
            "marked.scrollToLine(line)", arguments: ["line": line],
            in: nil, in: .defaultClient, completionHandler: nil)
    }

    /// Asks the page to report its position now (see `onScroll`).
    func reportScrollPosition() {
        guard pageLoaded, let webView else { return }
        webView.callAsyncJavaScript("marked.reportScroll()", arguments: [:], in: nil, in: .defaultClient, completionHandler: nil)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.scrollMessage, let line = message.body as? NSNumber else { return }
        onScroll?(line.doubleValue)
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
        let shell = Self.shellURL

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

    static let isolatedScript = #"""
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

      // Marked's own updates and programmatic scrolls aren't the user scrolling, so
      // scroll events are ignored for a moment after them.
      let quietUntil = 0;
      const quietFor = ms => { quietUntil = Math.max(quietUntil, performance.now() + ms); };

      let cachedBlocks = null;
      const blocks = () => cachedBlocks ??= Array.from(article().querySelectorAll('[data-sourcepos]'))
        .filter(el => el.parentElement === article() || el.matches('li, tr'));
      const pageTop = el => el.getBoundingClientRect().top + window.scrollY;
      const sourceEnd = el => parseInt(el.getAttribute('data-sourcepos').split('-')[1], 10) || sourceStart(el);

      // The inverse of scrollToLine: the source line at the top of the page.
      function topLine() {
        const list = blocks();
        if (window.scrollY <= 0 || list.length === 0) return 1;
        if (window.scrollY + window.innerHeight >= document.documentElement.scrollHeight - 1) return -1;
        const y = window.scrollY + 8;
        let low = 0, high = list.length - 1, found = -1;
        while (low <= high) {
          const mid = (low + high) >> 1;
          if (pageTop(list[mid]) <= y) { found = mid; low = mid + 1; } else { high = mid - 1; }
        }
        if (found < 0) return 1;
        const el = list[found], next = list[found + 1], a = sourceStart(el), top = pageTop(el);
        if (!next) {
          const span = Math.max(1, sourceEnd(el) - a + 1);
          return a + span * Math.min(1, (y - top) / Math.max(1, el.offsetHeight));
        }
        return a + (sourceStart(next) - a) * Math.min(1, (y - top) / Math.max(1, pageTop(next) - top));
      }

      const report = () => window.webkit?.messageHandlers?.previewScroll?.postMessage(topLine());

      let reportPending = false;
      window.addEventListener('scroll', () => {
        if (reportPending || performance.now() < quietUntil) return;
        reportPending = true;
        setTimeout(() => {
          reportPending = false;
          if (performance.now() >= quietUntil) report();
        }, 16);
      }, { passive: true });

      window.marked = {
        update(html, base) {
          const template = document.createElement('template');
          template.innerHTML = html;
          resolve(template.content, base);
          quietFor(300);
          cachedBlocks = null;
          article().replaceChildren(template.content);
        },

        reportScroll: report,

        scrollToLine(line) {
          quietFor(200);
          const list = blocks();
          if (line <= 1 || list.length === 0) { window.scrollTo(0, 0); return; }
          let before = null, after = null;
          for (const el of list) {
            const start = sourceStart(el);
            if (start <= line) before = el;
            else { after = el; break; }
          }
          let y;
          if (!before) {
            y = 0;
          } else if (!after) {
            const span = Math.max(1, sourceEnd(before) - sourceStart(before) + 1);
            y = pageTop(before) + before.offsetHeight * Math.min(1, (line - sourceStart(before)) / span);
          } else {
            const a = sourceStart(before), b = sourceStart(after);
            y = pageTop(before) + (pageTop(after) - pageTop(before)) * ((line - a) / Math.max(1, b - a));
          }
          window.scrollTo(0, Math.max(0, y - 8));
        },
      };
    })();
    """#
}

/// WKUserContentController retains its message handlers; this keeps it from
/// retaining the view controller that owns the web view.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

extension URL {
    var withoutFragment: URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.fragment = nil
        return components.url ?? self
    }
}
