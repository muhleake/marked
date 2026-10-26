import AppKit

final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let splitController: SplitViewController

    /// Per-window: a `.txt` document shown with Markdown preview and tinting.
    var treatsAsMarkdown = false

    var markdownDocument: MarkdownDocument? { document as? MarkdownDocument }
    var editorTextView: NSTextView? { splitController.editorController.textView }

    /// Markdown features (preview, tinting, toolbar actions) are on for this window.
    var isMarkdownEnabled: Bool { !(markdownDocument?.isPlainText ?? false) || treatsAsMarkdown }

    init(document: MarkdownDocument) {
        splitController = SplitViewController(document: document)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.minSize = NSSize(width: 480, height: 320)
        window.tabbingMode = .automatic
        window.tabbingIdentifier = "io.github.muhleake.marked.document"
        window.isRestorable = true
        window.contentViewController = splitController
        window.setContentSize(NSSize(width: 1100, height: 720))
        window.center()

        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = true

        splitController.layout = document.isPlainText ? .editorOnly : Preferences.defaultLayout
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Called when Save As changes the document between Markdown and plain text.
    func documentTypeDidChange() {
        guard let document = markdownDocument else { return }
        if !document.isPlainText { treatsAsMarkdown = false }
        if document.isPlainText && !treatsAsMarkdown {
            layout = .editorOnly
        } else if !document.isPlainText && layout == .editorOnly {
            layout = Preferences.defaultLayout
        }
        markdownModeDidChange()
    }

    // MARK: - Layout

    var layout: PreviewLayout {
        get { splitController.layout }
        set {
            splitController.layout = newValue
            if newValue == .split { splitController.syncPreviewScroll() }
            if newValue == .previewOnly, window?.firstResponder === editorTextView {
                window?.makeFirstResponder(splitController.previewController.webView)
            } else if newValue != .previewOnly, let editorTextView, window?.firstResponder !== editorTextView {
                window?.makeFirstResponder(editorTextView)
            }
        }
    }

    @objc func setPreviewLayout(_ sender: Any?) {
        guard isMarkdownEnabled, let item = sender as? NSValidatedUserInterfaceItem,
              PreviewLayout.allCases.indices.contains(item.tag) else { return }
        layout = PreviewLayout.allCases[item.tag]
    }

    /// ⌥⌘P: Split → Editor Only → Preview Only → Split.
    @objc func cyclePreviewLayout(_ sender: Any?) {
        guard isMarkdownEnabled else { return }
        layout = layout.next
    }

    /// View ▸ Treat as Markdown: preview and Markdown features for a `.txt` window,
    /// without renaming the file.
    @objc func toggleTreatAsMarkdown(_ sender: Any?) {
        guard markdownDocument?.isPlainText == true else { return }
        treatsAsMarkdown.toggle()
        layout = treatsAsMarkdown ? Preferences.defaultLayout : .editorOnly
        markdownModeDidChange()
    }

    /// Hook for features that depend on Markdown mode (toolbar, tinting).
    func markdownModeDidChange() {
        window?.toolbar?.validateVisibleItems()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(setPreviewLayout(_:)):
            item.state = PreviewLayout.allCases.indices.contains(item.tag) && layout == PreviewLayout.allCases[item.tag] ? .on : .off
            return isMarkdownEnabled
        case #selector(cyclePreviewLayout(_:)):
            return isMarkdownEnabled
        case #selector(toggleTreatAsMarkdown(_:)):
            let plain = markdownDocument?.isPlainText == true
            item.state = plain && treatsAsMarkdown ? .on : .off
            return plain
        default:
            return true
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        document?.undoManager
    }
}
