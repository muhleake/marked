import AppKit

/// Line numbers beside the editor. Numbers count lines in the file, so a long line
/// that wraps onto several rows gets one number. Only visible rows are drawn.
final class LineNumberRulerView: NSRulerView {
    /// 0-based line containing a UTF-16 offset.
    var lineIndex: (Int) -> Int = { _ in 0 }

    /// Number of lines in the file; sets the width.
    var lineCount = 1 {
        didSet { if digits(lineCount) != digits(oldValue) { updateThickness() } }
    }

    private var textView: NSTextView? { clientView as? NSTextView }
    private static let padding: CGFloat = 8

    init(textView: NSTextView, scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        // Numbers near the edges would otherwise draw over the status bar.
        clipsToBounds = true
        updateThickness()
        NotificationCenter.default.addObserver(
            self, selector: #selector(contentDidChange(_:)),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        if let storage = textView.textStorage {
            NotificationCenter.default.addObserver(
                self, selector: #selector(contentDidChange(_:)),
                name: NSTextStorage.didProcessEditingNotification, object: storage)
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func contentDidChange(_ note: Notification) { needsDisplay = true }

    private func digits(_ n: Int) -> Int { String(max(n, 1)).count }

    private var numberFont: NSFont {
        let size = (textView?.font?.pointSize ?? Preferences.editorFontSize) * 0.85
        return .monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }

    /// Fits the widest number, at least two digits, so the editor doesn't shift
    /// while the first lines are typed.
    func updateThickness() {
        let width = ("8" as NSString).size(withAttributes: [.font: numberFont]).width
        let thickness = ceil(CGFloat(max(digits(lineCount), 2)) * width + Self.padding * 2)
        if ruleThickness != thickness { ruleThickness = thickness }
    }

    override var requiredThickness: CGFloat { ruleThickness }

    override func draw(_ dirtyRect: NSRect) {
        (textView?.backgroundColor ?? .textBackgroundColor).setFill()
        dirtyRect.fill()
        drawHashMarksAndLabels(in: dirtyRect)
    }

    struct Label {
        let number: Int
        /// Top of the row in text container coordinates, and the baseline below it.
        let top: CGFloat
        let baseline: CGFloat
    }

    /// Numbers for the rows inside `visible` (text view coordinates): one per line, on
    /// the line's first row.
    func labels(in visible: NSRect) -> [Label] {
        guard let textView, let layoutManager = textView.layoutManager,
              let container = textView.textContainer, let storage = textView.textStorage else { return [] }
        let string = storage.string as NSString
        var labels: [Label] = []
        let origin = textView.textContainerOrigin
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible.offsetBy(dx: -origin.x, dy: -origin.y), in: container)
        var glyph = glyphs.location
        while glyph < NSMaxRange(glyphs) {
            var fragmentGlyphs = NSRange()
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &fragmentGlyphs)
            let char = layoutManager.characterIndexForGlyph(at: glyph)
            if char == 0 || string.character(at: char - 1) == 0x0A {
                labels.append(Label(number: lineIndex(char) + 1, top: fragment.minY,
                                    baseline: layoutManager.location(forGlyphAt: glyph).y))
            }
            glyph = max(NSMaxRange(fragmentGlyphs), glyph + 1)
        }

        // The empty last line after a final line break, or an empty file.
        let font = numberFont
        let extra = layoutManager.extraLineFragmentRect
        if !extra.isEmpty, extra.offsetBy(dx: origin.x, dy: origin.y).intersects(visible) {
            let baseline = font.ascender + max(0, extra.height - font.ascender + font.descender) / 2
            labels.append(Label(number: lineIndex(string.length) + 1, top: extra.minY, baseline: baseline))
        } else if string.length == 0 {
            labels.append(Label(number: 1, top: 0, baseline: font.ascender))
        }
        return labels
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView else { return }
        let font = numberFont
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
        let originY = convert(NSPoint.zero, from: textView).y + textView.textContainerOrigin.y
        for label in labels(in: textView.visibleRect) {
            let text = String(label.number) as NSString
            let width = text.size(withAttributes: attributes).width
            let top = originY + label.top + label.baseline - font.ascender
            text.draw(at: NSPoint(x: ruleThickness - Self.padding - width, y: top), withAttributes: attributes)
        }
    }
}
