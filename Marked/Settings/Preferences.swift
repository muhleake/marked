import AppKit

/// UserDefaults-backed settings.
enum Preferences {
    enum Key {
        static let editorFontSize = "EditorFontSize"
        static let defaultLayout = "DefaultMarkdownLayout"
        static let previewTheme = "PreviewTheme"
        static let previewZoom = "PreviewZoom"
        static let scalePreviewToWindow = "ScalePreviewToWindow"
        static let showLineNumbers = "ShowLineNumbers"
        static let showIndentGuides = "ShowIndentGuides"
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
    static let previewZoomRange: ClosedRange<Double> = 0.5...3
    static let previewZoomStep = 0.1

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.editorFontSize: Double(defaultFontSize),
            Key.defaultLayout: PreviewLayout.split.rawValue,
            Key.previewTheme: PreviewTheme.system.rawValue,
            Key.previewZoom: 1.0,
            Key.scalePreviewToWindow: false,
            Key.showLineNumbers: false,
            Key.showIndentGuides: false,
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

    /// Preview page zoom, 1 = 100%. Rounded so repeated steps land on whole percents.
    static var previewZoom: Double {
        get {
            let value = UserDefaults.standard.double(forKey: Key.previewZoom)
            return value > 0 ? value.clamped(to: previewZoomRange) : 1
        }
        set {
            let rounded = ((newValue * 100).rounded() / 100).clamped(to: previewZoomRange)
            UserDefaults.standard.set(rounded, forKey: Key.previewZoom)
            NotificationCenter.default.post(name: .previewZoomDidChange, object: nil)
        }
    }

    /// Scales the preview with its pane, on top of `previewZoom`.
    static var scalePreviewToWindow: Bool {
        get { UserDefaults.standard.bool(forKey: Key.scalePreviewToWindow) }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.scalePreviewToWindow)
            NotificationCenter.default.post(name: .previewZoomDidChange, object: nil)
        }
    }

    static var showLineNumbers: Bool {
        get { UserDefaults.standard.bool(forKey: Key.showLineNumbers) }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.showLineNumbers)
            NotificationCenter.default.post(name: .editorDisplayDidChange, object: nil)
        }
    }

    static var showIndentGuides: Bool {
        get { UserDefaults.standard.bool(forKey: Key.showIndentGuides) }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.showIndentGuides)
            NotificationCenter.default.post(name: .editorDisplayDidChange, object: nil)
        }
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
    static let editorDisplayDidChange = Notification.Name("MarkedEditorDisplayDidChange")
    static let previewThemeDidChange = Notification.Name("MarkedPreviewThemeDidChange")
    static let previewZoomDidChange = Notification.Name("MarkedPreviewZoomDidChange")
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
