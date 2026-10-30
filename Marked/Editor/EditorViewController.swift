import AppKit

/// The raw-text pane: an NSTextView on the document's text storage.
final class EditorViewController: NSViewController, NSTextViewDelegate {
    let textStorage: NSTextStorage
    private(set) var textView: NSTextView!
    private(set) var scrollView: NSScrollView!
    private(set) var statusLabel: NSTextField!
    private(set) var highlighter: MarkdownHighlighter!

    /// Tinting and list editing; off for plain .txt unless "Treat as Markdown".
    var isMarkdownEnabled = true {
        didSet { highlighter?.isEnabled = isMarkdownEnabled }
    }

    private static let countQueue = DispatchQueue(label: "io.github.muhleake.marked.counts", qos: .utility)
    private var pendingCount: DispatchWorkItem?
    private var countGeneration = 0
    /// Latest counts shown in the status bar (words, characters, lines).
    private(set) var counts = TextCounts(words: 0, characters: 0, lines: 0)

    /// Called (coalesced) when the visible text scrolls.
    var onScroll: (() -> Void)?
    private var scrollNotificationPending = false

    /// UTF-16 offsets where each line starts; rebuilt lazily after edits.
    private var lineStarts: [Int]?

    init(textStorage: NSTextStorage) {
        self.textStorage = textStorage
        super.init(nibName: nil, bundle: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(storageDidProcessEditing(_:)),
            name: NSTextStorage.didProcessEditingNotification, object: textStorage)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        // TextKit 1 stack so the view shares the document's NSTextStorage.
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        textStorage.addLayoutManager(layoutManager)

        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 600), textContainer: container)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        configure(textView)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        // Never auto-hide. With always-visible scroll bars, hiding one widens the text,
        // which re-wraps it, which can bring the scroll bar back. For text just taller
        // than the window that loops forever and freezes the app on open.
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.documentView = textView

        self.textView = textView
        self.scrollView = scrollView

        // Slim status bar: words · characters · lines.
        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setAccessibilityIdentifier("status")
        self.statusLabel = statusLabel
        let separator = NSBox()
        separator.boxType = .separator

        let root = NSView()
        for view in [scrollView, separator, statusLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            separator.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -12),
            statusLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 3),
            statusLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -4),
        ])
        view = root
        textView.delegate = self
        highlighter = MarkdownHighlighter(textStorage: textStorage, enabled: isMarkdownEnabled)
        applyFontSize()
        updateCounts(immediately: true)

        NotificationCenter.default.addObserver(
            self, selector: #selector(fontSizeDidChange(_:)), name: .editorFontSizeDidChange, object: nil)

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(visibleRectDidChange(_:)),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    @objc private func storageDidProcessEditing(_ note: Notification) {
        guard textStorage.editedMask.contains(.editedCharacters) else { return }
        lineStarts = nil
        updateCounts()
    }

    @objc private func fontSizeDidChange(_ note: Notification) {
        applyFontSize()
    }

    // MARK: - Status bar

    /// Counts off the main thread (word counting a long document isn't free),
    /// coalescing bursts of typing.
    func updateCounts(immediately: Bool = false) {
        pendingCount?.cancel()
        countGeneration += 1
        let generation = countGeneration
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let text = self.textStorage.string
            Self.countQueue.async {
                let counts = TextCounts(text)
                DispatchQueue.main.async {
                    guard generation == self.countGeneration else { return }
                    self.counts = counts
                    self.statusLabel.stringValue = counts.description
                }
            }
        }
        pendingCount = item
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediately ? 0 : 0.12), execute: item)
    }

    // MARK: - NSTextViewDelegate

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard isMarkdownEnabled else { return false }
        let text = textView.string, selection = textView.selectedRange()
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            guard let edit = ListContinuation.newline(in: text, selection: selection) else { return false }
            apply(edit, actionName: "Typing")
            return true
        case #selector(NSResponder.insertTab(_:)):
            guard let edit = ListContinuation.indent(in: text, selection: selection, outdent: false) else { return false }
            apply(edit, actionName: "Indent")
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            // Shift-Tab never moves focus out of the editor.
            if let edit = ListContinuation.indent(in: text, selection: selection, outdent: true) {
                apply(edit, actionName: "Outdent")
            }
            return true
        default:
            return false
        }
    }

    @objc private func visibleRectDidChange(_ note: Notification) {
        guard !scrollNotificationPending else { return }
        scrollNotificationPending = true
        DispatchQueue.main.async { [weak self] in
            self?.scrollNotificationPending = false
            self?.onScroll?()
        }
    }

    // MARK: - Visible position

    /// 1-based source line at the top of the editor, with a fraction for how far
    /// into that line the top edge falls (long wrapped lines scroll smoothly).
    func topVisibleSourceLine() -> Double {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer,
              textStorage.length > 0 else { return 1 }
        let visible = scrollView.contentView.bounds
        if visible.minY <= 0 { return 1 }
        if visible.maxY >= textView.frame.height - 1 { return Double(lineIndex(ofCharacterAt: textStorage.length - 1) + 1) + 0.999 }

        let origin = textView.textContainerOrigin
        let point = NSPoint(x: 0, y: visible.minY - origin.y)
        let glyph = layoutManager.glyphIndex(for: point, in: container)
        let char = layoutManager.characterIndexForGlyph(at: glyph)
        let line = lineIndex(ofCharacterAt: char)
        let starts = lineStartOffsets()
        let lineStart = starts[line]
        let lineEnd = line + 1 < starts.count ? starts[line + 1] : textStorage.length
        let fraction = lineEnd > lineStart ? Double(char - lineStart) / Double(lineEnd - lineStart) : 0
        return Double(line + 1) + min(fraction, 0.999)
    }

    /// Scrolls so the (fractional, 1-based) source line is at the top; the inverse of
    /// `topVisibleSourceLine`. `PreviewViewController.atDocumentEnd` scrolls to the end.
    func scroll(toSourceLine line: Double) {
        guard let layoutManager = textView.layoutManager, textStorage.length > 0 else { return }
        if line == PreviewViewController.atDocumentEnd {
            textView.scrollRangeToVisible(NSRange(location: textStorage.length, length: 0))
            return
        }
        var y: CGFloat = 0
        if line > 1 {
            let starts = lineStartOffsets()
            let index = min(Int(line) - 1, starts.count - 1)
            let lineEnd = index + 1 < starts.count ? starts[index + 1] : textStorage.length
            let offset = min(starts[index] + Int(Double(lineEnd - starts[index]) * (line - line.rounded(.down))), textStorage.length - 1)
            // Exact positions need layout up to this point (layout is non-contiguous).
            layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: offset + 1))
            let glyph = layoutManager.glyphIndexForCharacter(at: offset)
            y = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + textView.textContainerOrigin.y
        }
        let clip = scrollView.contentView
        clip.scroll(to: NSPoint(x: 0, y: min(y, max(0, textView.frame.height - clip.bounds.height))))
        scrollView.reflectScrolledClipView(clip)
    }

    /// 0-based line containing the UTF-16 offset.
    func lineIndex(ofCharacterAt offset: Int) -> Int {
        let starts = lineStartOffsets()
        var low = 0, high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    private func lineStartOffsets() -> [Int] {
        if let lineStarts { return lineStarts }
        var starts = [0]
        let string = textStorage.string as NSString
        let length = string.length
        var index = 0
        while index < length {
            let range = string.lineRange(for: NSRange(location: index, length: 0))
            index = NSMaxRange(range)
            if index < length || (index == length && length > 0 && string.character(at: length - 1) == 0x0A) {
                starts.append(index)
            }
        }
        lineStarts = starts
        return starts
    }

    private func configure(_ textView: NSTextView) {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.allowsDocumentBackgroundColorChange = false
        textView.textContainerInset = NSSize(width: 12, height: 10)

        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
    }

    /// Applies a Markdown command as a single undo step, then selects its result.
    func apply(_ edit: MarkdownEdit, actionName: String) {
        textView.breakUndoCoalescing()
        guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage.replaceCharacters(in: edit.range,
                                      with: NSAttributedString(string: edit.replacement, attributes: EditorStyle.baseAttributes()))
        textView.didChangeText()
        textView.undoManager?.setActionName(actionName)
        textView.setSelectedRange(edit.selection)
        textView.scrollRangeToVisible(edit.selection)
        textView.breakUndoCoalescing()
    }

    func applyFontSize() {
        let attributes = EditorStyle.baseAttributes()
        textView.font = attributes[.font] as? NSFont
        textView.defaultParagraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
        textView.typingAttributes = attributes
        highlighter?.highlightAll()
    }
}
