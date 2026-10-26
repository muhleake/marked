import Foundation

/// Return / Tab / Shift-Tab behavior for Markdown lists. Pure functions; nil
/// means "let NSTextView do its default".
enum ListContinuation {
    static let indentUnit = "    "

    private static let itemRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)(?:([-*+])([ \t]+)(\[[ xX]\][ \t]+)?|(\d{1,9})([.)])([ \t]+))"#)

    struct Item {
        let indent: String
        /// The whole prefix: indent + marker + spacing (+ checkbox).
        let prefixLength: Int
        let next: String
    }

    /// Parses a list item at the start of `line` and builds the next item's prefix.
    static func item(in line: String) -> Item? {
        let ns = line as NSString
        guard let m = itemRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let indent = ns.substring(with: m.range(at: 1))
        if m.range(at: 2).location != NSNotFound {
            let bullet = ns.substring(with: m.range(at: 2))
            let space = ns.substring(with: m.range(at: 3))
            let task = m.range(at: 4).location != NSNotFound ? "[ ] " : ""
            return Item(indent: indent, prefixLength: m.range.length, next: indent + bullet + space + task)
        }
        let number = Int(ns.substring(with: m.range(at: 5))) ?? 0
        let delimiter = ns.substring(with: m.range(at: 6))
        let space = ns.substring(with: m.range(at: 7))
        return Item(indent: indent, prefixLength: m.range.length, next: indent + "\(number + 1)" + delimiter + space)
    }

    /// Return: continue the list, or end it on an empty item.
    static func newline(in text: String, selection: NSRange) -> MarkdownEdit? {
        guard selection.length == 0 else { return nil }
        let s = text as NSString
        let lines = MarkdownCommands.allLines(of: s)
        let index = MarkdownCommands.lineIndex(containing: selection.location, in: lines)
        if isInsideFence(lineIndex: index, lines: lines) { return nil }
        let line = lines[index]
        guard let item = item(in: line.text) else { return nil }
        let column = selection.location - line.range.location
        guard column >= item.prefixLength else { return nil }

        let content = (line.text as NSString).substring(from: item.prefixLength)
        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            // Empty item: remove the marker and end the list.
            return MarkdownEdit(range: line.range, replacement: "", selection: NSRange(location: line.range.location, length: 0))
        }
        let insertion = "\n" + item.next
        return MarkdownEdit(range: selection, replacement: insertion,
                            selection: NSRange(location: selection.location + (insertion as NSString).length, length: 0))
    }

    /// Tab / Shift-Tab: indent or outdent every selected line. With no selection,
    /// only list items are (out)dented; Tab elsewhere types a tab as usual.
    static func indent(in text: String, selection: NSRange, outdent: Bool) -> MarkdownEdit? {
        let s = text as NSString
        let lines = MarkdownCommands.allLines(of: s)
        let first = MarkdownCommands.lineIndex(containing: selection.location, in: lines)
        var lastOffset = NSMaxRange(selection)
        if selection.length > 0, lastOffset > 0, s.character(at: lastOffset - 1) == 0x0A { lastOffset -= 1 }
        let last = max(first, MarkdownCommands.lineIndex(containing: lastOffset, in: lines))
        let selected = Array(lines[first...last])

        if selection.length == 0 {
            let line = selected[0]
            if !outdent && item(in: line.text) == nil { return nil }
        }

        var changes: [(old: MarkdownCommands.Line, new: String, delta: Int)] = []
        for line in selected {
            if outdent {
                let removed = outdentLength(of: line.text)
                changes.append((line, (line.text as NSString).substring(from: removed), -removed))
            } else if line.isBlank && selected.count > 1 {
                changes.append((line, line.text, 0))
            } else {
                changes.append((line, indentUnit + line.text, (indentUnit as NSString).length))
            }
        }
        if changes.allSatisfy({ $0.delta == 0 }) { return nil }

        let range = NSRange(location: selected.first!.range.location,
                            length: NSMaxRange(selected.last!.range) - selected.first!.range.location)
        let replacement = changes.map(\.new).joined(separator: "\n")
        let newSelection: NSRange
        if selection.length == 0 {
            let delta = changes[0].delta
            newSelection = NSRange(location: max(range.location, selection.location + delta), length: 0)
        } else {
            newSelection = NSRange(location: range.location, length: (replacement as NSString).length)
        }
        return MarkdownEdit(range: range, replacement: replacement, selection: newSelection)
    }

    private static func outdentLength(of line: String) -> Int {
        if line.hasPrefix("\t") { return 1 }
        return line.prefix(4).prefix { $0 == " " }.count
    }

    private static func isInsideFence(lineIndex: Int, lines: [MarkdownCommands.Line]) -> Bool {
        var open = false
        for line in lines[..<lineIndex] {
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { open.toggle() }
        }
        return open
    }
}
