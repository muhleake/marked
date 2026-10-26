import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
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
