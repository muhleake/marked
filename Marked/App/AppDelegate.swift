import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    static func main() {
        let app = NSApplication.shared
        // The first NSDocumentController created becomes the shared one.
        _ = MarkdownDocumentController()
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        NSWindow.allowsAutomaticWindowTabbing = true
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - Editor font size (Format ▸ Bigger / Smaller), persisted in UserDefaults

    @objc func makeTextBigger(_ sender: Any?) { Preferences.editorFontSize += 1 }
    @objc func makeTextSmaller(_ sender: Any?) { Preferences.editorFontSize -= 1 }
    @objc func resetTextSize(_ sender: Any?) { Preferences.editorFontSize = Preferences.defaultFontSize }

    // MARK: - Zoom (View menu), persisted in UserDefaults

    /// View ▸ Zoom In/Out: both panes together.
    @objc func zoomIn(_ sender: Any?) {
        Preferences.editorFontSize += 1
        previewZoomIn(sender)
    }

    @objc func zoomOut(_ sender: Any?) {
        Preferences.editorFontSize -= 1
        previewZoomOut(sender)
    }

    @objc func zoomToActualSize(_ sender: Any?) {
        resetTextSize(sender)
        previewZoomToActualSize(sender)
    }

    @objc func previewZoomIn(_ sender: Any?) { Preferences.previewZoom += Preferences.previewZoomStep }
    @objc func previewZoomOut(_ sender: Any?) { Preferences.previewZoom -= Preferences.previewZoomStep }
    @objc func previewZoomToActualSize(_ sender: Any?) { Preferences.previewZoom = 1 }
    @objc func toggleScalePreviewToWindow(_ sender: Any?) { Preferences.scalePreviewToWindow.toggle() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let zoom = Preferences.previewZoom, range = Preferences.previewZoomRange
        let size = Preferences.editorFontSize, sizes = Preferences.fontSizeRange
        switch item.action {
        case #selector(zoomIn(_:)): return zoom < range.upperBound || size < sizes.upperBound
        case #selector(zoomOut(_:)): return zoom > range.lowerBound || size > sizes.lowerBound
        case #selector(zoomToActualSize(_:)): return zoom != 1 || size != Preferences.defaultFontSize
        case #selector(previewZoomIn(_:)): return zoom < range.upperBound
        case #selector(previewZoomOut(_:)): return zoom > range.lowerBound
        case #selector(previewZoomToActualSize(_:)): return zoom != 1
        case #selector(toggleScalePreviewToWindow(_:)):
            item.state = Preferences.scalePreviewToWindow ? .on : .off
            return true
        default: return true
        }
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.showWindow(sender)
    }

    /// Catches edits made by other apps while Marked was in the background, in case
    /// a file-presenter notification was missed.
    func applicationDidBecomeActive(_ notification: Notification) {
        for case let document as MarkdownDocument in NSDocumentController.shared.documents {
            document.checkForExternalChange()
        }
    }
}
