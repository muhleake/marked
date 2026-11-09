import AppKit

/// The editor's text view. Draws indentation guides: a faint vertical line at each
/// indent level (four spaces or a tab) of a line's leading whitespace.
final class EditorTextView: NSTextView {
    static let indentWidth = 4

    var showsIndentGuides = false {
        didSet { if showsIndentGuides != oldValue { needsDisplay = true } }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        if showsIndentGuides { drawIndentGuides(in: rect) }
    }

    private func drawIndentGuides(in rect: NSRect) {
        guard let layoutManager, let textContainer, let textStorage, let font else { return }
        let string = textStorage.string as NSString
        let space = (" " as NSString).size(withAttributes: [.font: font]).width
        let origin = textContainerOrigin
        let left = origin.x + textContainer.lineFragmentPadding
        let lineWidth = 1 / (window?.backingScaleFactor ?? 2)
        NSColor.separatorColor.setFill()

        let glyphs = layoutManager.glyphRange(forBoundingRect: rect.offsetBy(dx: -origin.x, dy: -origin.y), in: textContainer)
        var glyph = glyphs.location
        while glyph < NSMaxRange(glyphs) {
            var fragmentGlyphs = NSRange()
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &fragmentGlyphs)
            let char = layoutManager.characterIndexForGlyph(at: glyph)
            // Only a line's first row starts with its indentation; wrapped rows don't.
            if char == 0 || string.character(at: char - 1) == 0x0A {
                let levels = Self.indentColumns(in: string, from: char) / Self.indentWidth
                for level in 0..<levels {
                    let x = left + CGFloat(level * Self.indentWidth) * space
                    NSRect(x: x, y: origin.y + fragment.minY, width: lineWidth, height: fragment.height).fill()
                }
            }
            glyph = max(NSMaxRange(fragmentGlyphs), glyph + 1)
        }
    }

    /// Columns of leading whitespace on the line starting at `start`, counting a tab as
    /// moving to the next indent stop. Whitespace-only lines count as unindented.
    static func indentColumns(in string: NSString, from start: Int) -> Int {
        var columns = 0, index = start
        while index < string.length {
            switch string.character(at: index) {
            case 0x20: columns += 1
            case 0x09: columns += indentWidth - columns % indentWidth
            case 0x0A: return 0
            default: return columns
            }
            index += 1
        }
        return 0
    }
}
