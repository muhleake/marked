import AppKit

/// UserDefaults-backed settings.
enum Preferences {
    enum Key {
        static let editorFontSize = "EditorFontSize"
        static let defaultLayout = "DefaultMarkdownLayout"
    }

    static let fontSizeRange: ClosedRange<CGFloat> = 9...36
    static let defaultFontSize: CGFloat = 13

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.editorFontSize: Double(defaultFontSize),
            Key.defaultLayout: PreviewLayout.split.rawValue,
            // Markdown is corrupted by smart substitutions; keep them off app-wide.
            "NSAutomaticQuoteSubstitutionEnabled": false,
            "NSAutomaticDashSubstitutionEnabled": false,
            "NSAutomaticTextReplacementEnabled": false,
            "NSAutomaticSpellingCorrectionEnabled": false,
        ])
    }

    static var editorFontSize: CGFloat {
        get {
            let value = CGFloat(UserDefaults.standard.double(forKey: Key.editorFontSize))
            return value > 0 ? value.clamped(to: fontSizeRange) : defaultFontSize
        }
        set {
            UserDefaults.standard.set(Double(newValue.clamped(to: fontSizeRange)), forKey: Key.editorFontSize)
            NotificationCenter.default.post(name: .editorFontSizeDidChange, object: nil)
        }
    }

    static var defaultLayout: PreviewLayout {
        get { PreviewLayout(rawValue: UserDefaults.standard.string(forKey: Key.defaultLayout) ?? "") ?? .split }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.defaultLayout) }
    }
}

extension Notification.Name {
    static let editorFontSizeDidChange = Notification.Name("MarkedEditorFontSizeDidChange")
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
