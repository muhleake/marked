import AppKit

final class DocumentWindowController: NSWindowController, NSWindowDelegate {
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
        guard let document = markdownDocument, !treatsAsMarkdown else { return }
        if document.isPlainText {
            splitController.layout = .editorOnly
        } else if splitController.layout == .editorOnly {
            splitController.layout = Preferences.defaultLayout
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        document?.undoManager
    }
}
