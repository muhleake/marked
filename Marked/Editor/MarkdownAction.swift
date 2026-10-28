import AppKit

/// Every Markdown formatting action, shared by the toolbar and the Format menu.
/// The raw value is used as the menu item / toolbar item tag.
enum MarkdownAction: Int, CaseIterable {
    case bold, italic, strikethrough
    case heading1, heading2, heading3, heading4, heading5, heading6
    case bulletList, numberedList, taskList, quote
    case inlineCode, codeBlock
    case link, image, table, horizontalRule
    // Added later; kept at the end so saved toolbar layouts (keyed by raw value) stay valid.
    case underline, highlight

    static let headings: [MarkdownAction] = [.heading1, .heading2, .heading3, .heading4, .heading5, .heading6]

    var title: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .strikethrough: "Strikethrough"
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6: "Heading \(headingLevel!)"
        case .bulletList: "Bulleted List"
        case .numberedList: "Numbered List"
        case .taskList: "Task List"
        case .quote: "Quote"
        case .inlineCode: "Inline Code"
        case .codeBlock: "Code Block"
        case .link: "Link"
        case .image: "Image"
        case .table: "Table"
        case .horizontalRule: "Horizontal Rule"
        case .underline: "Underline"
        case .highlight: "Highlight"
        }
    }

    var symbolName: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strikethrough"
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6: "number"
        case .bulletList: "list.bullet"
        case .numberedList: "list.number"
        case .taskList: "checklist"
        case .quote: "text.quote"
        case .inlineCode: "chevron.left.forwardslash.chevron.right"
        case .codeBlock: "curlybraces.square"
        case .link: "link"
        case .image: "photo"
        case .table: "tablecells"
        case .horizontalRule: "minus"
        case .underline: "underline"
        case .highlight: "highlighter"
        }
    }

    /// Key equivalents from the spec's toolbar table. Shifted keys use the shifted
    /// character (⇧⌘8 is "*"), which is what AppKit matches against.
    var shortcut: (key: String, modifiers: NSEvent.ModifierFlags) {
        switch self {
        case .bold: ("b", .command)
        case .italic: ("i", .command)
        case .strikethrough: ("X", .command)
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6: ("\(headingLevel!)", .command)
        case .bulletList: ("*", .command)
        case .numberedList: ("&", .command)
        case .taskList: ("T", .command)
        case .quote: (">", .command)
        case .inlineCode: ("c", [.command, .option])
        case .codeBlock: ("C", .command)
        case .link: ("k", .command)
        case .image: ("I", .command)
        case .table: ("t", [.command, .option])
        case .horizontalRule: ("_", .command)
        case .underline: ("u", .command)
        case .highlight: ("H", .command)
        }
    }

    var headingLevel: Int? {
        guard let index = Self.headings.firstIndex(of: self) else { return nil }
        return index + 1
    }

    func edit(in text: String, selection: NSRange) -> MarkdownEdit {
        switch self {
        case .bold: MarkdownCommands.toggleInline(.bold, in: text, selection: selection)
        case .italic: MarkdownCommands.toggleInline(.italic, in: text, selection: selection)
        case .strikethrough: MarkdownCommands.toggleInline(.strikethrough, in: text, selection: selection)
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            MarkdownCommands.toggleHeading(level: headingLevel!, in: text, selection: selection)
        case .bulletList: MarkdownCommands.toggleList(.bullet, in: text, selection: selection)
        case .numberedList: MarkdownCommands.toggleList(.numbered, in: text, selection: selection)
        case .taskList: MarkdownCommands.toggleList(.task, in: text, selection: selection)
        case .quote: MarkdownCommands.toggleQuote(in: text, selection: selection)
        case .inlineCode: MarkdownCommands.toggleInline(.code, in: text, selection: selection)
        case .codeBlock: MarkdownCommands.toggleCodeBlock(in: text, selection: selection)
        case .link: MarkdownCommands.toggleLink(in: text, selection: selection)
        case .image: MarkdownCommands.toggleImage(in: text, selection: selection)
        case .table: MarkdownCommands.toggleTable(in: text, selection: selection)
        case .horizontalRule: MarkdownCommands.toggleHorizontalRule(in: text, selection: selection)
        case .underline: MarkdownCommands.toggleTag(.underline, in: text, selection: selection)
        case .highlight: MarkdownCommands.toggleTag(.highlight, in: text, selection: selection)
        }
    }

    func menuItem() -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(DocumentWindowController.applyMarkdownAction(_:)),
                              keyEquivalent: shortcut.key)
        item.keyEquivalentModifierMask = shortcut.modifiers
        item.tag = rawValue
        return item
    }
}

/// Format ▸ Text Color presets. Mid-tone colors that read on both the light and
/// dark preview backgrounds.
enum TextColor: String, CaseIterable {
    case red, orange, yellow, green, blue, purple, pink, gray

    var title: String { rawValue.capitalized }

    var hex: String {
        switch self {
        case .red: "#e5484d"
        case .orange: "#f76b15"
        case .yellow: "#d4a72c"
        case .green: "#30a46c"
        case .blue: "#0090ff"
        case .purple: "#8e4ec6"
        case .pink: "#d6409f"
        case .gray: "#8b8d98"
        }
    }

    var color: NSColor { NSColor(hexString: hex) ?? .labelColor }

    /// A round swatch for menus.
    var swatch: NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            self.color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.accessibilityDescription = title
        return image
    }

    /// The Text Color menu: one item per preset plus Remove Color. The item's
    /// representedObject is the hex string (nil for Remove Color).
    static func menu() -> NSMenu {
        let menu = NSMenu(title: "Text Color")
        for color in allCases {
            let item = NSMenuItem(title: color.title, action: #selector(DocumentWindowController.applyTextColor(_:)), keyEquivalent: "")
            item.representedObject = color.hex
            item.image = color.swatch
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Remove Color", action: #selector(DocumentWindowController.applyTextColor(_:)), keyEquivalent: ""))
        return menu
    }
}

extension NSColor {
    /// "#rrggbb" → color (sRGB). Nil for anything else.
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
