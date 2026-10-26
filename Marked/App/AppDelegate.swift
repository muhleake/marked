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
        // Settings window arrives in Phase 6.
    }
}
