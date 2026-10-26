import AppKit

/// Tints raw Markdown in the editor: color and weight only, never hiding characters.
///
/// As the text storage's delegate it re-tints just the edited paragraphs. A change
/// that adds, removes or edits a code fence re-tints the whole document, since it
/// flips everything after it in or out of a code block.
final class MarkdownHighlighter: NSObject, NSTextStorageDelegate {
    private weak var textStorage: NSTextStorage?
    private var fenceLineStarts: [Int] = []
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
        let newFences = Self.fenceLineStarts(in: string)
        let paragraphs = string.paragraphRange(for: editedRange)
        let touchesFence = newFences.contains { NSLocationInRange($0, paragraphs) || $0 == NSMaxRange(paragraphs) }
        let fencesChanged = newFences.count != fenceLineStarts.count || touchesFence
        fenceLineStarts = newFences
        if fencesChanged {
            apply(to: NSRange(location: 0, length: string.length), in: textStorage)
        } else {
            apply(to: paragraphs, in: textStorage)
        }
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

        let string = storage.string as NSString
        let bold = EditorStyle.boldFont(size: size)
        let italic = NSFontManager.shared.convert(EditorStyle.font(size: size), toHaveTrait: .italicFontMask)
        let boldItalic = NSFontManager.shared.convert(bold, toHaveTrait: .italicFontMask)
        let color = { (r: NSRange, c: NSColor) in storage.addAttribute(.foregroundColor, value: c, range: r) }
        let font = { (r: NSRange, f: NSFont) in storage.addAttribute(.font, value: f, range: r) }

        // Line-level constructs, skipping fenced code.
        string.enumerateSubstrings(in: range, options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            if self.isInFencedBlock(line.location) {
                color(line, Palette.code)
                return
            }
            if let m = Self.heading.firstMatch(in: string as String, range: line) {
                color(m.range, Palette.heading)
                font(m.range, bold)
                color(m.range(at: 1), Palette.marker)
                return
            }
            if let m = Self.rule.firstMatch(in: string as String, range: line) {
                color(m.range, Palette.rule)
                return
            }
            if let m = Self.quote.firstMatch(in: string as String, range: line) {
                color(line, Palette.quote)
                color(m.range, Palette.quoteMarker)
            }
            if let m = Self.listMarker.firstMatch(in: string as String, range: line) {
                color(m.range(at: 1), Palette.listMarker)
                if m.range(at: 2).location != NSNotFound { color(m.range(at: 2), Palette.listMarker) }
            }
            self.applyInline(in: line, string: string, color: color, font: font,
                             bold: bold, italic: italic, boldItalic: boldItalic)
        }
    }

    private func applyInline(in line: NSRange, string: NSString,
                             color: (NSRange, NSColor) -> Void, font: (NSRange, NSFont) -> Void,
                             bold: NSFont, italic: NSFont, boldItalic: NSFont) {
        let s = string as String
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
        var i = 0
        while i < fenceLineStarts.count {
            if lineStart < fenceLineStarts[i] { return false }
            guard i + 1 < fenceLineStarts.count else { return true }
            if lineStart <= fenceLineStarts[i + 1] { return true }
            i += 2
        }
        return false
    }

    static func fenceLineStarts(in s: NSString) -> [Int] {
        var starts: [Int] = []
        for fence in ["```", "~~~"] {
            var search = NSRange(location: 0, length: s.length)
            while true {
                let found = s.range(of: fence, options: [], range: search)
                if found.location == NSNotFound { break }
                let lineStart = s.lineRange(for: NSRange(location: found.location, length: 0)).location
                let prefix = s.substring(with: NSRange(location: lineStart, length: found.location - lineStart))
                if prefix.allSatisfy({ $0 == " " }) && prefix.count <= 3, starts.last != lineStart {
                    starts.append(lineStart)
                }
                let next = s.lineRange(for: found)
                search = NSRange(location: NSMaxRange(next), length: s.length - NSMaxRange(next))
                if search.length <= 0 { break }
            }
        }
        return Array(Set(starts)).sorted()
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
