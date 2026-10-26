import AppKit

/// The raw-text pane: an NSTextView on the document's text storage.
final class EditorViewController: NSViewController {
    let textStorage: NSTextStorage
    private(set) var textView: NSTextView!
    private(set) var scrollView: NSScrollView!

    init(textStorage: NSTextStorage) {
        self.textStorage = textStorage
        super.init(nibName: nil, bundle: nil)
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

    func applyFontSize() {
        let attributes = EditorStyle.baseAttributes()
        textView.font = attributes[.font] as? NSFont
        textView.defaultParagraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
        textView.typingAttributes = attributes
        let full = NSRange(location: 0, length: textStorage.length)
        textStorage.addAttributes(attributes, range: full)
    }
}
