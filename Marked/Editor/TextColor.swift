import AppKit

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
