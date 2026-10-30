import AppKit

/// Tints raw Markdown in the editor: color and weight only, never hiding characters.
///
/// As the text storage's delegate it re-tints just the edited paragraphs. A change
/// that adds, removes or edits a code fence re-tints the whole document, since it
/// flips everything after it in or out of a code block.
final class MarkdownHighlighter: NSObject, NSTextStorageDelegate {
    private weak var textStorage: NSTextStorage?
    /// UTF-16 offsets of the code-fence lines, ascending.
    private(set) var fenceLineStarts: [Int] = []
    private var isApplying = false

    var isEnabled: Bool {
        didSet { if isEnabled != oldValue { highlightAll() } }
    }

    init(textStorage: NSTextStorage, enabled: Bool) {
        self.textStorage = textStorage
        self.isEnabled = enabled
        super.init()
        textStorage.delegate = self
        highlightAll()
    }

    // MARK: - Colors (system colors, so dark mode works)

    enum Palette {
        static var heading: NSColor { .systemBlue }
        static var marker: NSColor { .tertiaryLabelColor }
        static var code: NSColor { .systemPink }
        static var link: NSColor { .systemBlue }
        static var url: NSColor { .secondaryLabelColor }
        static var listMarker: NSColor { .systemOrange }
        static var quote: NSColor { .secondaryLabelColor }
        static var quoteMarker: NSColor { .systemGreen }
        static var strikethrough: NSColor { .secondaryLabelColor }
        static var rule: NSColor { .tertiaryLabelColor }
    }

    // MARK: - NSTextStorageDelegate

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), !isApplying else { return }
        let string = textStorage.string as NSString
        // One character past the edit: Return in mid-line ends the edit at a line
        // break, and the text pushed onto the new line needs tinting too.
        let reach = NSRange(location: editedRange.location,
                            length: min(editedRange.length + 1, string.length - editedRange.location))
        let paragraphs = string.paragraphRange(for: reach)
        if updateFences(editedParagraphs: paragraphs, delta: delta, in: string) {
            apply(to: NSRange(location: 0, length: string.length), in: textStorage)
        } else {
            apply(to: paragraphs, in: textStorage)
        }
    }

    /// Keeps the fence list current by rescanning only the edited paragraphs; fences
    /// after them just shift. Returns true if the text after the edit flipped in or
    /// out of a code block, which only an odd change in the number of fences can do.
    private func updateFences(editedParagraphs paragraphs: NSRange, delta: Int, in string: NSString) -> Bool {
        let oldEnd = NSMaxRange(paragraphs) - delta
        let before = fenceLineStarts.prefix { $0 < paragraphs.location }
        let after = fenceLineStarts.drop { $0 < oldEnd }
        let removed = fenceLineStarts[before.endIndex..<after.startIndex]
        let found = Self.fenceLineStarts(in: string, range: paragraphs)
        fenceLineStarts = Array(before) + found + after.map { $0 + delta }
        return (found.count - removed.count) % 2 != 0
    }

    // MARK: - Highlighting

    func highlightAll() {
        guard let textStorage else { return }
        fenceLineStarts = Self.fenceLineStarts(in: textStorage.string as NSString)
        textStorage.beginEditing()
        apply(to: NSRange(location: 0, length: textStorage.length), in: textStorage)
        textStorage.endEditing()
    }

    private func apply(to range: NSRange, in storage: NSTextStorage) {
        guard range.length > 0 else { return }
        isApplying = true
        defer { isApplying = false }

        let size = Preferences.editorFontSize
        storage.setAttributes(EditorStyle.baseAttributes(size: size), range: range)
        guard isEnabled else { return }

        // One copy of just this range. Converting the storage's whole string per
        // line made tinting cost grow with the document instead of the edit.
        let text = (storage.string as NSString).substring(with: range)
        let shift = range.location
        let bold = EditorStyle.boldFont(size: size)
        let italic = NSFontManager.shared.convert(EditorStyle.font(size: size), toHaveTrait: .italicFontMask)
        let boldItalic = NSFontManager.shared.convert(bold, toHaveTrait: .italicFontMask)
        let inStorage = { (r: NSRange) in NSRange(location: r.location + shift, length: r.length) }
        let color = { (r: NSRange, c: NSColor) in storage.addAttribute(.foregroundColor, value: c, range: inStorage(r)) }
        let font = { (r: NSRange, f: NSFont) in storage.addAttribute(.font, value: f, range: inStorage(r)) }

        // Line-level constructs, skipping fenced code.
        let whole = NSRange(location: 0, length: (text as NSString).length)
        (text as NSString).enumerateSubstrings(in: whole, options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            if self.isInFencedBlock(line.location + shift) {
                color(line, Palette.code)
                return
            }
            if let m = Self.heading.firstMatch(in: text, range: line) {
                color(m.range, Palette.heading)
                font(m.range, bold)
                color(m.range(at: 1), Palette.marker)
                return
            }
            if let m = Self.rule.firstMatch(in: text, range: line) {
                color(m.range, Palette.rule)
                return
            }
            if let m = Self.quote.firstMatch(in: text, range: line) {
                color(line, Palette.quote)
                color(m.range, Palette.quoteMarker)
            }
            if let m = Self.listMarker.firstMatch(in: text, range: line) {
                color(m.range(at: 1), Palette.listMarker)
                if m.range(at: 2).location != NSNotFound { color(m.range(at: 2), Palette.listMarker) }
            }
            self.applyInline(in: line, text: text, color: color, font: font,
                             bold: bold, italic: italic, boldItalic: boldItalic)
        }
    }

    private func applyInline(in line: NSRange, text s: String,
                             color: (NSRange, NSColor) -> Void, font: (NSRange, NSFont) -> Void,
                             bold: NSFont, italic: NSFont, boldItalic: NSFont) {
        for m in Self.boldItalic.matches(in: s, range: line) {
            font(m.range, boldItalic)
            color(m.range(at: 1), Palette.marker)
            color(m.range(at: 3), Palette.marker)
        }
        for m in Self.bold.matches(in: s, range: line) {
            font(m.range, bold)
            color(m.range(at: 1), Palette.marker)
            color(m.range(at: 3), Palette.marker)
        }
        for m in Self.italic.matches(in: s, range: line) {
            font(m.range, italic)
            color(m.range(at: 1), Palette.marker)
            color(m.range(at: 3), Palette.marker)
        }
        for m in Self.strikethrough.matches(in: s, range: line) {
            color(m.range, Palette.strikethrough)
        }
        for m in Self.link.matches(in: s, range: line) {
            color(m.range(at: 1), Palette.link)
            color(m.range(at: 2), Palette.url)
        }
        for m in Self.bareURL.matches(in: s, range: line) {
            color(m.range, Palette.link)
        }
        // Code last: nothing inside a code span is emphasis.
        for m in Self.inlineCode.matches(in: s, range: line) {
            font(m.range, EditorStyle.font(size: Preferences.editorFontSize))
            color(m.range, Palette.code)
        }
    }

    // MARK: - Fences

    /// Fence lines pair up as open/close; an unclosed fence runs to the end.
    /// Fence lines themselves count as part of their block.
    private func isInFencedBlock(_ lineStart: Int) -> Bool {
        // How many fences start at or before this line (binary search: this runs per line).
        var low = 0, high = fenceLineStarts.count
        while low < high {
            let mid = (low + high) / 2
            if fenceLineStarts[mid] <= lineStart { low = mid + 1 } else { high = mid }
        }
        // Odd: an open fence is unclosed here. Even: inside only on the closing line itself.
        return low % 2 == 1 || (low > 0 && fenceLineStarts[low - 1] == lineStart)
    }

    /// Starts of the fence lines (up to 3 spaces, then ``` or ~~~) in `range`, ascending.
    static func fenceLineStarts(in s: NSString, range: NSRange? = nil) -> [Int] {
        let range = range ?? NSRange(location: 0, length: s.length)
        var starts = Set<Int>()
        for fence in ["```", "~~~"] {
            var search = range
            while search.length > 0 {
                let found = s.range(of: fence, options: [], range: search)
                if found.location == NSNotFound { break }
                let line = s.lineRange(for: NSRange(location: found.location, length: 0))
                let prefix = s.substring(with: NSRange(location: line.location, length: found.location - line.location))
                if prefix.count <= 3, prefix.allSatisfy({ $0 == " " }) { starts.insert(line.location) }
                let next = min(NSMaxRange(line), NSMaxRange(range))
                search = NSRange(location: next, length: NSMaxRange(range) - next)
            }
        }
        return starts.sorted()
    }

    // MARK: - Patterns

    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    static let heading = regex(#"^(#{1,6})(?:[ \t].*)?$"#, .anchorsMatchLines)
    static let rule = regex(#"^[ \t]{0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#, .anchorsMatchLines)
    static let quote = regex(#"^[ \t]{0,3}(?:>[ \t]?)+"#, .anchorsMatchLines)
    static let listMarker = regex(#"^[ \t]*(?:>[ \t]?)*[ \t]*([-*+]|\d{1,9}[.)])[ \t]+(\[[ xX]\])?"#, .anchorsMatchLines)
    static let boldItalic = regex(#"(\*\*\*|___)(?=\S)(.+?)(?<=\S)(\1)"#)
    static let bold = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)(\1)"#)
    static let italic = regex(#"(?<![*_\w])([*_])(?=[^\s*_])(.+?)(?<=[^\s*_])(\1)(?![*_\w])"#)
    static let strikethrough = regex(#"~~(?=\S).+?(?<=\S)~~"#)
    static let link = regex(#"!?(\[[^\]\n]*\])(\([^)\n]*\))"#)
    static let bareURL = regex(#"(?<![(<\[])\b(?:https?://|www\.)[^\s<>()]+"#)
    static let inlineCode = regex(#"(`+)[^`\n]+?\1"#)
}
