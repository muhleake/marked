import AppKit

/// Marked ▸ Settings… (⌘,): editor font size, default layout for Markdown, preview theme.
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private let sizeField = NSTextField()
    private let sizeStepper = NSStepper()
    private let layoutPopUp = NSPopUpButton()
    private let themePopUp = NSPopUpButton()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
                              styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "Settings"
        window.isRestorable = false
        super.init(window: window)
        buildContent()
        refresh()
        window.center()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .editorFontSizeDidChange, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildContent() {
        sizeField.formatter = {
            let formatter = NumberFormatter()
            formatter.minimum = Preferences.fontSizeRange.lowerBound as NSNumber
            formatter.maximum = Preferences.fontSizeRange.upperBound as NSNumber
            formatter.maximumFractionDigits = 0
            return formatter
        }()
        sizeField.alignment = .right
        sizeField.target = self
        sizeField.action = #selector(sizeFieldChanged(_:))
        sizeField.widthAnchor.constraint(equalToConstant: 44).isActive = true
        sizeStepper.minValue = Double(Preferences.fontSizeRange.lowerBound)
        sizeStepper.maxValue = Double(Preferences.fontSizeRange.upperBound)
        sizeStepper.increment = 1
        sizeStepper.target = self
        sizeStepper.action = #selector(sizeStepperChanged(_:))
        let sizeRow = NSStackView(views: [sizeField, sizeStepper, NSTextField(labelWithString: "pt")])
        sizeRow.spacing = 4

        layoutPopUp.addItems(withTitles: PreviewLayout.allCases.map(\.title))
        layoutPopUp.target = self
        layoutPopUp.action = #selector(layoutChanged(_:))

        themePopUp.addItems(withTitles: Preferences.PreviewTheme.allCases.map(\.title))
        themePopUp.target = self
        themePopUp.action = #selector(themeChanged(_:))

        let note = NSTextField(wrappingLabelWithString: "Plain text (.txt) files always open editor-only; use View ▸ Treat as Markdown for a window.")
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.textColor = .secondaryLabelColor

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Editor font size:"), sizeRow],
            [NSTextField(labelWithString: "Markdown files open in:"), layoutPopUp],
            [NSTextField(labelWithString: "Preview theme:"), themePopUp],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 10
        grid.columnSpacing = 8

        let stack = NSStackView(views: [grid, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        note.widthAnchor.constraint(equalToConstant: 360).isActive = true
        window?.contentView = stack
    }

    @objc private func refresh() {
        sizeField.integerValue = Int(Preferences.editorFontSize)
        sizeStepper.integerValue = Int(Preferences.editorFontSize)
        layoutPopUp.selectItem(at: PreviewLayout.allCases.firstIndex(of: Preferences.defaultLayout) ?? 0)
        themePopUp.selectItem(at: Preferences.PreviewTheme.allCases.firstIndex(of: Preferences.previewTheme) ?? 0)
    }

    @objc func sizeFieldChanged(_ sender: NSTextField) { Preferences.editorFontSize = CGFloat(sender.integerValue) }
    @objc func sizeStepperChanged(_ sender: NSStepper) { Preferences.editorFontSize = CGFloat(sender.integerValue) }

    @objc func layoutChanged(_ sender: NSPopUpButton) {
        Preferences.defaultLayout = PreviewLayout.allCases[max(0, sender.indexOfSelectedItem)]
    }

    @objc func themeChanged(_ sender: NSPopUpButton) {
        Preferences.previewTheme = Preferences.PreviewTheme.allCases[max(0, sender.indexOfSelectedItem)]
    }

    // Exposed for tests.
    var controls: (size: NSTextField, stepper: NSStepper, layout: NSPopUpButton, theme: NSPopUpButton) {
        (sizeField, sizeStepper, layoutPopUp, themePopUp)
    }
}
