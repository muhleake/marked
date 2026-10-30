import Foundation

/// One text change: replace `range` with `replacement`, then select `selection`
/// (in the resulting text). All ranges are UTF-16, like NSString/NSTextView.
struct MarkdownEdit: Equatable {
    var range: NSRange
    var replacement: String
    var selection: NSRange

    /// The full resulting text (for tests and pure use).
    func applied(to text: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: replacement)
    }
}

enum InlineStyle: CaseIterable {
    case bold, italic, strikethrough, code

    var marker: String {
        switch self {
        case .bold: "**"
        case .italic: "*"
        case .strikethrough: "~~"
        case .code: "`"
        }
    }

    /// Characters that can form this style's marker run (`_` also makes emphasis).
    fileprivate var markerCharacters: [unichar] {
        switch self {
        case .bold, .italic: [Character("*").utf16Unit, Character("_").utf16Unit]
        case .strikethrough: [Character("~").utf16Unit]
        case .code: [Character("`").utf16Unit]
        }
    }

    /// Whether a run of `length` marker characters carries this style.
    /// A run of 3 asterisks is both bold and italic.
    fileprivate func matches(run length: Int) -> Bool {
        switch self {
        case .bold: length == 2 || length == 3
        case .italic: length == 1 || length == 3
        case .strikethrough: length == 2
        case .code: length == 1
        }
    }

    fileprivate var width: Int { marker.utf16.count }
}

enum ListKind: Equatable {
    case bullet, numbered, task
}

/// Pure Markdown text transforms behind the toolbar and Format menu.
/// Each takes the text and selection and returns one edit (one undo step).
enum MarkdownCommands {

    // MARK: - Inline styles

    static func toggleInline(_ style: InlineStyle, in text: String, selection: NSRange) -> MarkdownEdit {
        let s = text as NSString
        let width = style.width

        if selection.length > 0 {
            // The selection includes its markers: "**text**" → "text".
            let selected = s.substring(with: selection) as NSString
            for c in style.markerCharacters {
                let lead = runLength(of: c, in: selected, from: 0)
                let trail = runLength(of: c, in: selected, before: selected.length)
                if lead < selected.length, style.matches(run: lead), style.matches(run: trail) {
                    let inner = selected.substring(with: NSRange(location: width, length: selected.length - 2 * width))
                    return MarkdownEdit(range: selection, replacement: inner,
                                        selection: NSRange(location: selection.location, length: (inner as NSString).length))
                }
            }
            // Markers sit just outside the selection: **[text]** → text.
            for c in style.markerCharacters {
                let before = runLength(of: c, in: s, before: selection.location)
                let after = runLength(of: c, in: s, from: NSMaxRange(selection))
                if style.matches(run: before), style.matches(run: after) {
                    let range = NSRange(location: selection.location - width, length: selection.length + 2 * width)
                    return MarkdownEdit(range: range, replacement: s.substring(with: selection),
                                        selection: NSRange(location: range.location, length: selection.length))
                }
            }
            // Wrap, keeping surrounding whitespace outside the markers.
            let core = trimmedWhitespace(selection, in: s)
            guard core.length > 0 else {
                return insertPair(style, at: NSMaxRange(selection), replacing: selection)
            }
            let wrapped = style.marker + s.substring(with: core) + style.marker
            return MarkdownEdit(range: core, replacement: wrapped,
                                selection: NSRange(location: core.location + width, length: core.length))
        }

        let cursor = selection.location
        // Cursor between an empty pair: "**|**" → "".
        for c in style.markerCharacters {
            let before = runLength(of: c, in: s, before: cursor)
            let after = runLength(of: c, in: s, from: cursor)
            if before == after, style.matches(run: before) {
                return MarkdownEdit(range: NSRange(location: cursor - width, length: 2 * width), replacement: "",
                                    selection: NSRange(location: cursor - width, length: 0))
            }
        }
        // Cursor inside a styled span on this line: "**te|xt**" → "te|xt".
        if let span = enclosingSpan(style, around: cursor, in: s) {
            let inner = s.substring(with: NSRange(location: span.open + width, length: span.close - span.open - width))
            return MarkdownEdit(range: NSRange(location: span.open, length: span.close + width - span.open),
                                replacement: inner, selection: NSRange(location: cursor - width, length: 0))
        }
        return insertPair(style, at: cursor, replacing: selection)
    }

    private static func insertPair(_ style: InlineStyle, at cursor: Int, replacing range: NSRange) -> MarkdownEdit {
        MarkdownEdit(range: range, replacement: style.marker + style.marker,
                     selection: NSRange(location: range.location + style.width, length: 0))
    }

    /// Finds marker runs for `style` on the cursor's line. If an odd number of them
    /// come before the cursor, it's inside a span closed by the next one.
    /// Returns the UTF-16 offsets where the opening marker starts and the closing one starts.
    private static func enclosingSpan(_ style: InlineStyle, around cursor: Int, in s: NSString) -> (open: Int, close: Int)? {
        let line = s.lineRange(for: NSRange(location: cursor, length: 0))
        let width = style.width
        for c in style.markerCharacters {
            var runs: [(start: Int, length: Int)] = []
            var i = line.location
            let end = NSMaxRange(line)
            while i < end {
                if s.character(at: i) == c {
                    let length = runLength(of: c, in: s, from: i)
                    if style.matches(run: length) { runs.append((i, length)) }
                    i += length
                } else {
                    i += 1
                }
            }
            let before = runs.filter { $0.start + $0.length <= cursor }
            guard before.count % 2 == 1, let open = before.last,
                  let close = runs.first(where: { $0.start >= cursor }) else { continue }
            // Strip the markers nearest the text: the end of the opening run, the start of the closing one.
            return (open.start + open.length - width, close.start)
        }
        return nil
    }

    // MARK: - Line prefixes

    static func toggleHeading(level: Int, in text: String, selection: NSRange) -> MarkdownEdit {
        precondition((1...6).contains(level))
        let marker = String(repeating: "#", count: level) + " "
        return transformLines(in: text, selection: selection) { lines in
            let target = lines.filter { !$0.isBlank }
            let considered = target.isEmpty ? lines : target
            let allHave = considered.allSatisfy { headingLevel(of: $0.text) == level }
            return lines.map { line in
                guard considered.contains(where: { $0.range == line.range }) else { return line.edit(prefixLength: 0, newPrefix: "") }
                let existing = headingPrefixLength(of: line.text)
                return line.edit(prefixLength: existing, newPrefix: allHave ? "" : marker)
            }
        }
    }

    static func toggleList(_ kind: ListKind, in text: String, selection: NSRange) -> MarkdownEdit {
        transformLines(in: text, selection: selection) { lines in
            let target = lines.filter { !$0.isBlank }
            let considered = target.isEmpty ? lines : target
            let allHave = considered.allSatisfy { listMarker(in: $0.text)?.kind == kind }
            var number = 0
            return lines.map { line in
                guard considered.contains(where: { $0.range == line.range }) else { return line.edit(prefixLength: 0, newPrefix: "") }
                let existing = listMarker(in: line.text)
                let indent = leadingWhitespace(of: line.text)
                let oldPrefix = existing.map { $0.length } ?? indent.utf16.count
                if allHave { return line.edit(prefixLength: oldPrefix, newPrefix: indent) }
                number += 1
                let marker: String
                switch kind {
                case .bullet: marker = "- "
                case .numbered: marker = "\(number). "
                case .task: marker = "- [ ] "
                }
                return line.edit(prefixLength: oldPrefix, newPrefix: indent + marker)
            }
        }
    }

    static func toggleQuote(in text: String, selection: NSRange) -> MarkdownEdit {
        transformLines(in: text, selection: selection) { lines in
            let target = lines.filter { !$0.isBlank }
            let considered = target.isEmpty ? lines : target
            let allHave = considered.allSatisfy { quotePrefixLength(of: $0.text) > 0 }
            return lines.map { line in
                let existing = quotePrefixLength(of: line.text)
                if allHave { return line.edit(prefixLength: existing, newPrefix: "") }
                if existing > 0 { return line.edit(prefixLength: 0, newPrefix: "") }
                // Blank lines inside a multi-line quote get a bare ">" to keep it one block.
                if line.isBlank && lines.count > 1 { return line.edit(prefixLength: 0, newPrefix: ">") }
                return line.edit(prefixLength: 0, newPrefix: "> ")
            }
        }
    }

    // MARK: - Code block

    static func toggleCodeBlock(in text: String, selection: NSRange) -> MarkdownEdit {
        let s = text as NSString
        let lines = allLines(of: s)
        let firstIndex = lineIndex(containing: selection.location, in: lines)
        let lastOffset = selection.length > 0 ? NSMaxRange(selection) - 1 : selection.location
        let lastIndex = max(firstIndex, lineIndex(containing: lastOffset, in: lines))

        // Inside an existing fenced block (or selecting its fences)? Remove the fences.
        if let block = fencedBlock(enclosing: firstIndex...lastIndex, in: lines, s) {
            let open = lines[block.lowerBound], close = lines[block.upperBound]
            let interiorStart = NSMaxRange(open.range) + 1
            let interior = close.range.location > interiorStart
                ? s.substring(with: NSRange(location: interiorStart, length: close.range.location - 1 - interiorStart)) : ""
            let range = NSRange(location: open.range.location, length: NSMaxRange(close.range) - open.range.location)
            let shift = interiorStart - open.range.location
            var newSelection = NSRange(location: max(range.location, selection.location - shift), length: 0)
            if selection.length > 0 { newSelection = NSRange(location: range.location, length: (interior as NSString).length) }
            return MarkdownEdit(range: range, replacement: interior, selection: newSelection)
        }

        let start = lines[firstIndex].range.location
        let end = NSMaxRange(lines[lastIndex].range)
        let body = s.substring(with: NSRange(location: start, length: end - start))
        let replacement = "```\n" + body + "\n```"
        // Cursor after the opening fence, ready for a language name.
        return MarkdownEdit(range: NSRange(location: start, length: end - start), replacement: replacement,
                            selection: NSRange(location: start + 3, length: 0))
    }

    private static func isFence(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```") || line.trimmingCharacters(in: .whitespaces).hasPrefix("~~~")
    }

    /// Indices of the opening and closing fence lines of the block containing `span`.
    private static func fencedBlock(enclosing span: ClosedRange<Int>, in lines: [Line], _ s: NSString) -> ClosedRange<Int>? {
        var open: Int?
        for (index, line) in lines.enumerated() where isFence(line.text) {
            if let start = open {
                if start <= span.lowerBound && index >= span.upperBound { return start...index }
                open = nil
            } else {
                open = index
            }
        }
        return nil
    }

    // MARK: - Links and images

    private static let linkPattern = try! NSRegularExpression(pattern: #"(!?)\[([^\]\n]*)\]\(([^)\n]*)\)"#)

    static func toggleLink(in text: String, selection: NSRange) -> MarkdownEdit {
        toggleLinkLike(image: false, in: text, selection: selection)
    }

    static func toggleImage(in text: String, selection: NSRange) -> MarkdownEdit {
        toggleLinkLike(image: true, in: text, selection: selection)
    }

    private static func toggleLinkLike(image: Bool, in text: String, selection: NSRange) -> MarkdownEdit {
        let s = text as NSString
        let line = s.lineRange(for: selection)
        // Inside an existing link/image: unlink, keeping its text.
        for match in linkPattern.matches(in: text, range: line) {
            let isImage = match.range(at: 1).length > 0
            let inside = selection.length == 0
                ? match.range.location < selection.location && selection.location < NSMaxRange(match.range)
                : match.range.location <= selection.location && NSMaxRange(selection) <= NSMaxRange(match.range)
            guard isImage == image, inside else { continue }
            let label = s.substring(with: match.range(at: 2))
            return MarkdownEdit(range: match.range, replacement: label,
                                selection: NSRange(location: match.range.location, length: (label as NSString).length))
        }

        let bang = image ? "!" : ""
        let placeholderText = image ? "alt" : "text"
        let placeholderTarget = image ? "path" : "url"
        let selected = s.substring(with: selection)

        if selection.length > 0 && looksLikeTarget(selected, image: image) {
            // Selected a URL/path: it becomes the target; select the label placeholder.
            let replacement = "\(bang)[\(placeholderText)](\(selected))"
            let labelStart = selection.location + (bang as NSString).length + 1
            return MarkdownEdit(range: selection, replacement: replacement,
                                selection: NSRange(location: labelStart, length: (placeholderText as NSString).length))
        }
        let label = selection.length > 0 ? selected : placeholderText
        let replacement = "\(bang)[\(label)](\(placeholderTarget))"
        // Cursor lands in the (url): the placeholder is selected so typing replaces it.
        let targetStart = selection.location + (replacement as NSString).length - 1 - (placeholderTarget as NSString).length
        return MarkdownEdit(range: selection, replacement: replacement,
                            selection: NSRange(location: targetStart, length: (placeholderTarget as NSString).length))
    }

    private static func looksLikeTarget(_ string: String, image: Bool) -> Bool {
        let lower = string.lowercased()
        if lower.contains(" ") || lower.contains("\n") { return false }
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.") || lower.hasPrefix("mailto:") { return true }
        if image { return [".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".heic"].contains { lower.hasSuffix($0) } }
        return false
    }

    // MARK: - Table and rule

    static let tableSkeleton = """
    | Column 1 | Column 2 | Column 3 |
    | -------- | -------- | -------- |
    |          |          |          |
    |          |          |          |
    """

    static func toggleTable(in text: String, selection: NSRange) -> MarkdownEdit {
        let s = text as NSString
        let lines = allLines(of: s)
        let current = lineIndex(containing: selection.location, in: lines)

        // Cursor in an untouched skeleton: remove it.
        let skeletonLines = tableSkeleton.components(separatedBy: "\n")
        for start in max(0, current - skeletonLines.count + 1)...current where start + skeletonLines.count <= lines.count {
            let block = lines[start..<(start + skeletonLines.count)]
            if block.map(\.text) == skeletonLines {
                var range = NSRange(location: block.first!.range.location,
                                    length: NSMaxRange(block.last!.range) - block.first!.range.location)
                // Also drop the line break after it, if any.
                if NSMaxRange(range) < s.length { range.length += 1 }
                return MarkdownEdit(range: range, replacement: "", selection: NSRange(location: range.location, length: 0))
            }
        }
        // Inside some other table: add the new one after it, not in the middle.
        var anchor = selection
        if lines[current].text.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
            var last = current
            while last + 1 < lines.count, lines[last + 1].text.trimmingCharacters(in: .whitespaces).hasPrefix("|") { last += 1 }
            anchor = NSRange(location: NSMaxRange(lines[last].range), length: 0)
        }
        return insertBlock(tableSkeleton, in: s, selection: anchor,
                           select: NSRange(location: 2, length: ("Column 1" as NSString).length))
    }

    static func toggleHorizontalRule(in text: String, selection: NSRange) -> MarkdownEdit {
        let s = text as NSString
        let line = s.lineRange(for: NSRange(location: selection.location, length: 0))
        let content = s.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
        if ["---", "***", "___"].contains(content) {
            return MarkdownEdit(range: line, replacement: "", selection: NSRange(location: line.location, length: 0))
        }
        return insertBlock("---", in: s, selection: selection, select: NSRange(location: 3, length: 0), cursorAfter: true)
    }

    /// Puts `block` on its own lines with a blank line before and after (a rule right
    /// under text would turn that text into a heading). `select` is relative to the block.
    private static func insertBlock(_ block: String, in s: NSString, selection: NSRange, select: NSRange,
                                    cursorAfter: Bool = false) -> MarkdownEdit {
        let lines = allLines(of: s)
        let index = lineIndex(containing: NSMaxRange(selection), in: lines)
        let line = lines[index]
        let hasNewlineAfter = NSMaxRange(line.range) < s.length

        let range: NSRange
        var prefix = ""
        if line.isBlank {
            // Use the blank line itself.
            range = line.range
            if index > 0, !lines[index - 1].isBlank { prefix = "\n" }
        } else {
            // Start a new paragraph after the current line.
            range = NSRange(location: NSMaxRange(line.range), length: 0)
            prefix = "\n\n"
        }
        var suffix = "\n"
        if hasNewlineAfter {
            suffix = index + 1 < lines.count && !lines[index + 1].isBlank ? "\n" : ""
        }

        let replacement = prefix + block + suffix
        let blockStart = range.location + (prefix as NSString).length
        let newSelection: NSRange
        if cursorAfter {
            // Start of the line after the block.
            let after = blockStart + (block as NSString).length + 1
            newSelection = NSRange(location: min(after, s.length - range.length + (replacement as NSString).length), length: 0)
        } else {
            newSelection = NSRange(location: blockStart + select.location, length: select.length)
        }
        return MarkdownEdit(range: range, replacement: replacement, selection: newSelection)
    }

    // MARK: - Line model

    struct Line {
        /// Content range, without the line break.
        let range: NSRange
        let text: String
        var isBlank: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

        func edit(prefixLength: Int, newPrefix: String) -> LineChange {
            LineChange(line: self, removed: prefixLength, added: newPrefix)
        }
    }

    struct LineChange {
        let line: Line
        let removed: Int
        let added: String
        var newText: String { added + (line.text as NSString).substring(from: removed) }
    }

    static func allLines(of s: NSString) -> [Line] {
        var lines: [Line] = []
        var start = 0
        while true {
            let search = NSRange(location: start, length: s.length - start)
            let newline = s.range(of: "\n", options: [], range: search)
            let end = newline.location == NSNotFound ? s.length : newline.location
            let range = NSRange(location: start, length: end - start)
            lines.append(Line(range: range, text: s.substring(with: range)))
            if newline.location == NSNotFound { break }
            start = end + 1
        }
        return lines
    }

    static func lineIndex(containing offset: Int, in lines: [Line]) -> Int {
        for (index, line) in lines.enumerated() where offset <= NSMaxRange(line.range) {
            return index
        }
        return lines.count - 1
    }

    /// Applies per-line prefix changes to every line the selection touches.
    private static func transformLines(in text: String, selection: NSRange,
                                       _ transform: ([Line]) -> [LineChange]) -> MarkdownEdit {
        let s = text as NSString
        let all = allLines(of: s)
        let first = lineIndex(containing: selection.location, in: all)
        // A selection ending at the start of a line doesn't include that line.
        var lastOffset = NSMaxRange(selection)
        if selection.length > 0, lastOffset > 0, s.character(at: lastOffset - 1) == 0x0A { lastOffset -= 1 }
        let last = max(first, lineIndex(containing: lastOffset, in: all))
        let lines = Array(all[first...last])
        let changes = transform(lines)

        let range = NSRange(location: lines.first!.range.location,
                            length: NSMaxRange(lines.last!.range) - lines.first!.range.location)
        let replacement = changes.map(\.newText).joined(separator: "\n")

        let newSelection: NSRange
        if selection.length == 0, let change = changes.first {
            // Keep the cursor at the same spot in the line's content.
            let column = selection.location - change.line.range.location
            let added = (change.added as NSString).length
            let newColumn = max(added, column - change.removed + added)
            newSelection = NSRange(location: range.location + min(newColumn, (change.newText as NSString).length), length: 0)
        } else {
            newSelection = NSRange(location: range.location, length: (replacement as NSString).length)
        }
        return MarkdownEdit(range: range, replacement: replacement, selection: newSelection)
    }

    // MARK: - Line parsing

    private static let headingRegex = try! NSRegularExpression(pattern: #"^(#{1,6})(?:[ \t]+|$)"#)
    private static let listRegex = try! NSRegularExpression(pattern: #"^([ \t]*)(?:([-*+])[ \t]+(\[[ xX]\][ \t]+)?|(\d{1,9})[.)][ \t]+)"#)
    private static let quoteRegex = try! NSRegularExpression(pattern: #"^>[ ]?"#)

    static func headingLevel(of line: String) -> Int? {
        let ns = line as NSString
        guard let match = headingRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return match.range(at: 1).length
    }

    private static func headingPrefixLength(of line: String) -> Int {
        let ns = line as NSString
        return headingRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))?.range.length ?? 0
    }

    /// The list marker at the start of a line (after indentation), with its total prefix length.
    static func listMarker(in line: String) -> (kind: ListKind, length: Int)? {
        let ns = line as NSString
        guard let match = listRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        if match.range(at: 4).location != NSNotFound { return (.numbered, match.range.length) }
        if match.range(at: 3).location != NSNotFound { return (.task, match.range.length) }
        return (.bullet, match.range.length)
    }

    private static func quotePrefixLength(of line: String) -> Int {
        let ns = line as NSString
        return quoteRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))?.range.length ?? 0
    }

    static func leadingWhitespace(of line: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" })
    }

    // MARK: - Character helpers

    /// Number of consecutive `c` characters ending just before `index`.
    private static func runLength(of c: unichar, in s: NSString, before index: Int) -> Int {
        var i = index - 1, n = 0
        while i >= 0, s.character(at: i) == c { n += 1; i -= 1 }
        return n
    }

    /// Number of consecutive `c` characters starting at `index`.
    private static func runLength(of c: unichar, in s: NSString, from index: Int) -> Int {
        var i = index, n = 0
        while i < s.length, s.character(at: i) == c { n += 1; i += 1 }
        return n
    }

    private static func trimmedWhitespace(_ range: NSRange, in s: NSString) -> NSRange {
        var start = range.location, end = NSMaxRange(range)
        let ws = CharacterSet.whitespacesAndNewlines
        while start < end, let scalar = UnicodeScalar(s.character(at: start)), ws.contains(scalar) { start += 1 }
        while end > start, let scalar = UnicodeScalar(s.character(at: end - 1)), ws.contains(scalar) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }
}

private extension Character {
    var utf16Unit: unichar { utf16.first! }
}
