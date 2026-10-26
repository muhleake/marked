import AppKit

/// The raw-text pane: an NSTextView on the document's text storage.
final class EditorViewController: NSViewController {
    let textStorage: NSTextStorage
    private(set) var textView: NSTextView!
    private(set) var scrollView: NSScrollView!

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
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.documentView = textView

        self.textView = textView
        self.scrollView = scrollView

        let root = NSView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
        applyFontSize()

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(visibleRectDidChange(_:)),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    @objc private func storageDidProcessEditing(_ note: Notification) {
        if textStorage.editedMask.contains(.editedCharacters) { lineStarts = nil }
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
        let full = NSRange(location: 0, length: textStorage.length)
        textStorage.addAttributes(attributes, range: full)
    }
}
