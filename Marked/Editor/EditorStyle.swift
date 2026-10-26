import AppKit

/// Base typography for the raw-text editor.
enum EditorStyle {
    static func font(size: CGFloat = Preferences.editorFontSize) -> NSFont {
        // The monospaced system font is SF Mono.
        .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func boldFont(size: CGFloat = Preferences.editorFontSize) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: .bold)
    }

    static func paragraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.2
        return style
    }

    static func baseAttributes(size: CGFloat = Preferences.editorFontSize) -> [NSAttributedString.Key: Any] {
        [
            .font: font(size: size),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle(),
        ]
    }
}
