import AppKit

/// UserDefaults-backed settings.
enum Preferences {
    enum Key {
        static let editorFontSize = "EditorFontSize"
        static let defaultLayout = "DefaultMarkdownLayout"
        static let previewTheme = "PreviewTheme"
    }

    enum PreviewTheme: String, CaseIterable {
        case system, light, dark

        var title: String {
            switch self {
            case .system: "Match System"
            case .light: "Light"
            case .dark: "Dark"
            }
        }

        var appearance: NSAppearance? {
            switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
            }
        }
    }

    static let fontSizeRange: ClosedRange<CGFloat> = 9...36
    static let defaultFontSize: CGFloat = 13

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.editorFontSize: Double(defaultFontSize),
            Key.defaultLayout: PreviewLayout.split.rawValue,
            Key.previewTheme: PreviewTheme.system.rawValue,
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

    static var previewTheme: PreviewTheme {
        get { PreviewTheme(rawValue: UserDefaults.standard.string(forKey: Key.previewTheme) ?? "") ?? .system }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Key.previewTheme)
            NotificationCenter.default.post(name: .previewThemeDidChange, object: nil)
        }
    }
}

extension Notification.Name {
    static let editorFontSizeDidChange = Notification.Name("MarkedEditorFontSizeDidChange")
    static let previewThemeDidChange = Notification.Name("MarkedPreviewThemeDidChange")
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
