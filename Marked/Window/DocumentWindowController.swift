import AppKit

final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, NSToolbarItemValidation {
    let splitController: SplitViewController
    private(set) var toolbarController: ToolbarController!

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

        toolbarController = ToolbarController(windowController: self)
        window.toolbar = toolbarController.makeToolbar()
        window.toolbarStyle = .expanded

        splitController.layout = document.isPlainText ? .editorOnly : Preferences.defaultLayout
        // `self.document` isn't set until addWindowController, so use the parameter.
        splitController.editorController.isMarkdownEnabled = !document.isPlainText
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
            toolbarController?.syncLayout()
            window?.invalidateRestorableState()
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
        setTreatsAsMarkdown(!treatsAsMarkdown)
    }

    private func setTreatsAsMarkdown(_ on: Bool) {
        treatsAsMarkdown = on
        layout = on ? Preferences.defaultLayout : .editorOnly
        markdownModeDidChange()
        window?.invalidateRestorableState()
    }

    /// Hook for features that depend on Markdown mode (toolbar, tinting).
    func markdownModeDidChange() {
        splitController.editorController.isMarkdownEnabled = isMarkdownEnabled
        toolbarController?.syncLayout()
        for item in window?.toolbar?.items ?? []
        where [ToolbarController.headingItem, ToolbarController.textColorItem].contains(item.itemIdentifier) {
            item.isEnabled = canApplyMarkdown
        }
        window?.toolbar?.validateVisibleItems()
    }

    // MARK: - Markdown actions

    /// Formatting applies to the editor; off for plain .txt and while the editor is hidden.
    var canApplyMarkdown: Bool { isMarkdownEnabled && layout != .previewOnly }

    /// Toolbar buttons and Format menu items; the sender's tag is a MarkdownAction.
    @objc func applyMarkdownAction(_ sender: Any?) {
        guard canApplyMarkdown, let tag = (sender as? NSValidatedUserInterfaceItem)?.tag,
              let action = MarkdownAction(rawValue: tag) else { NSSound.beep(); return }
        let editor = splitController.editorController
        window?.makeFirstResponder(editor.textView)
        editor.apply(action.edit(in: editor.textView.string, selection: editor.textView.selectedRange()),
                     actionName: action.title)
    }

    /// Format ▸ Text Color and the toolbar color menu. The item's representedObject
    /// is the color's hex string; nil means Remove Color.
    @objc func applyTextColor(_ sender: Any?) {
        guard canApplyMarkdown else { NSSound.beep(); return }
        let editor = splitController.editorController
        let text = editor.textView.string, selection = editor.textView.selectedRange()
        window?.makeFirstResponder(editor.textView)
        if let hex = (sender as? NSMenuItem)?.representedObject as? String {
            editor.apply(MarkdownCommands.toggleTag(.color(hex), in: text, selection: selection), actionName: "Text Color")
        } else if let edit = MarkdownCommands.removeColor(in: text, selection: selection) {
            editor.apply(edit, actionName: "Remove Color")
        } else {
            NSSound.beep()
        }
    }

    // MARK: - Copy as HTML

    /// Edit ▸ Copy as HTML: the rendered HTML of the selection, or of the whole
    /// document when nothing is selected. Goes on the pasteboard as HTML and as text.
    @objc func copyAsHTML(_ sender: Any?) {
        guard let textView = editorTextView else { return }
        let selection = textView.selectedRange()
        let source = selection.length > 0 ? (textView.string as NSString).substring(with: selection) : textView.string
        let html = MarkdownRenderer.html(from: source, sourcePositions: false)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(html, forType: .html)
        pasteboard.setString(html, forType: .string)
    }

    // MARK: - State restoration (layout and Treat as Markdown, per window)

    private enum RestorationKey {
        static let layout = "MarkedLayout"
        static let treatsAsMarkdown = "MarkedTreatsAsMarkdown"
    }

    func window(_ window: NSWindow, willEncodeRestorableState state: NSCoder) {
        state.encode(layout.rawValue as NSString, forKey: RestorationKey.layout)
        state.encode(treatsAsMarkdown, forKey: RestorationKey.treatsAsMarkdown)
    }

    func window(_ window: NSWindow, didDecodeRestorableState state: NSCoder) {
        if state.decodeBool(forKey: RestorationKey.treatsAsMarkdown), markdownDocument?.isPlainText == true {
            setTreatsAsMarkdown(true)
        }
        if let raw = state.decodeObject(of: NSString.self, forKey: RestorationKey.layout),
           let restored = PreviewLayout(rawValue: raw as String), isMarkdownEnabled {
            layout = restored
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        item.action == #selector(applyMarkdownAction(_:)) ? canApplyMarkdown : true
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(setPreviewLayout(_:)):
            item.state = PreviewLayout.allCases.indices.contains(item.tag) && layout == PreviewLayout.allCases[item.tag] ? .on : .off
            return isMarkdownEnabled
        case #selector(cyclePreviewLayout(_:)):
            return isMarkdownEnabled
        case #selector(applyMarkdownAction(_:)), #selector(applyTextColor(_:)):
            return canApplyMarkdown
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
