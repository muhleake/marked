import AppKit

/// The main menu, built in code (documented in docs/BEHAVIOR.md). AppKit adds Duplicate, Rename, Move To, Revert To,
/// Share and the window-tab items at runtime.
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu(title: "Main Menu")
        main.addItem(submenu: appMenu())
        main.addItem(submenu: fileMenu())
        main.addItem(submenu: editMenu())
        main.addItem(submenu: formatMenu())
        main.addItem(submenu: viewMenu())

        let window = windowMenu()
        main.addItem(submenu: window)
        NSApp.windowsMenu = window

        let help = NSMenu(title: "Help")
        main.addItem(submenu: help)
        NSApp.helpMenu = help
        return main
    }

    // MARK: - App

    private static func appMenu() -> NSMenu {
        let name = ProcessInfo.processInfo.processName
        let menu = NSMenu(title: name)
        menu.addItem("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        menu.addItem(.separator())
        menu.addItem("Settings…", #selector(AppDelegate.showSettings(_:)), ",")
        menu.addItem(.separator())
        let services = NSMenu(title: "Services")
        menu.addItem(submenu: services)
        NSApp.servicesMenu = services
        menu.addItem(.separator())
        menu.addItem("Hide \(name)", #selector(NSApplication.hide(_:)), "h")
        menu.addItem("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        menu.addItem("Show All", #selector(NSApplication.unhideAllApplications(_:)))
        menu.addItem(.separator())
        menu.addItem("Quit \(name)", #selector(NSApplication.terminate(_:)), "q")
        return menu
    }

    // MARK: - File

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem("New", #selector(NSDocumentController.newDocument(_:)), "n")
        menu.addItem("Open…", #selector(NSDocumentController.openDocument(_:)), "o")

        let recent = NSMenu(title: "Open Recent")
        // AppKit recognizes this menu by its Clear Menu action and fills it on open.
        recent.addItem("Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:)))
        menu.addItem(submenu: recent)

        menu.addItem(.separator())
        menu.addItem("Close", #selector(NSWindow.performClose(_:)), "w")
        menu.addItem("Save", #selector(NSDocument.save(_:)), "s")
        menu.addItem("Save As…", #selector(NSDocument.saveAs(_:)), "S")
        menu.addItem("Revert to Saved", #selector(NSDocument.revertToSaved(_:)))
        menu.addItem("Export as PDF…", #selector(NSDocument.saveToPDF(_:)))
        menu.addItem(.separator())
        menu.addItem("Page Setup…", #selector(NSDocument.runPageLayout(_:)), "P")
        menu.addItem("Print…", #selector(NSDocument.printDocument(_:)), "p")
        return menu
    }

    // MARK: - Edit

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem("Undo", Selector(("undo:")), "z")
        menu.addItem("Redo", Selector(("redo:")), "Z")
        menu.addItem(.separator())
        menu.addItem("Cut", #selector(NSText.cut(_:)), "x")
        menu.addItem("Copy", #selector(NSText.copy(_:)), "c")
        menu.addItem("Paste", #selector(NSText.paste(_:)), "v")
        menu.addItem("Copy as HTML", #selector(DocumentWindowController.copyAsHTML(_:)))
        menu.addItem("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "V", [.command, .option])
        menu.addItem("Delete", #selector(NSText.delete(_:)))
        menu.addItem("Select All", #selector(NSText.selectAll(_:)), "a")
        menu.addItem(.separator())
        menu.addItem(submenu: findMenu())
        menu.addItem(submenu: spellingMenu())
        menu.addItem(submenu: substitutionsMenu())
        menu.addItem(submenu: transformationsMenu())
        menu.addItem(submenu: speechMenu())
        return menu
    }

    private static func findMenu() -> NSMenu {
        let menu = NSMenu(title: "Find")
        let find = #selector(NSResponder.performTextFinderAction(_:))
        menu.addItem("Find…", find, "f").tag = NSTextFinder.Action.showFindInterface.rawValue
        menu.addItem("Find and Replace…", find, "f", [.command, .option]).tag = NSTextFinder.Action.showReplaceInterface.rawValue
        menu.addItem("Find Next", find, "g").tag = NSTextFinder.Action.nextMatch.rawValue
        menu.addItem("Find Previous", find, "G").tag = NSTextFinder.Action.previousMatch.rawValue
        menu.addItem("Use Selection for Find", find, "e").tag = NSTextFinder.Action.setSearchString.rawValue
        menu.addItem("Jump to Selection", #selector(NSTextView.centerSelectionInVisibleArea(_:)), "j")
        return menu
    }

    private static func spellingMenu() -> NSMenu {
        let menu = NSMenu(title: "Spelling and Grammar")
        menu.addItem("Show Spelling and Grammar", #selector(NSText.showGuessPanel(_:)), ":")
        menu.addItem("Check Document Now", #selector(NSText.checkSpelling(_:)), ";")
        menu.addItem(.separator())
        menu.addItem("Check Spelling While Typing", #selector(NSTextView.toggleContinuousSpellChecking(_:)))
        menu.addItem("Check Grammar With Spelling", #selector(NSTextView.toggleGrammarChecking(_:)))
        menu.addItem("Correct Spelling Automatically", #selector(NSTextView.toggleAutomaticSpellingCorrection(_:)))
        return menu
    }

    private static func substitutionsMenu() -> NSMenu {
        let menu = NSMenu(title: "Substitutions")
        menu.addItem("Show Substitutions", #selector(NSTextView.orderFrontSubstitutionsPanel(_:)))
        menu.addItem(.separator())
        menu.addItem("Smart Copy/Paste", #selector(NSTextView.toggleSmartInsertDelete(_:)))
        menu.addItem("Smart Quotes", #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:)))
        menu.addItem("Smart Dashes", #selector(NSTextView.toggleAutomaticDashSubstitution(_:)))
        menu.addItem("Smart Links", #selector(NSTextView.toggleAutomaticLinkDetection(_:)))
        menu.addItem("Data Detectors", #selector(NSTextView.toggleAutomaticDataDetection(_:)))
        menu.addItem("Text Replacement", #selector(NSTextView.toggleAutomaticTextReplacement(_:)))
        return menu
    }

    private static func transformationsMenu() -> NSMenu {
        let menu = NSMenu(title: "Transformations")
        menu.addItem("Make Upper Case", #selector(NSResponder.uppercaseWord(_:)))
        menu.addItem("Make Lower Case", #selector(NSResponder.lowercaseWord(_:)))
        menu.addItem("Capitalize", #selector(NSResponder.capitalizeWord(_:)))
        return menu
    }

    private static func speechMenu() -> NSMenu {
        let menu = NSMenu(title: "Speech")
        menu.addItem("Start Speaking", #selector(NSTextView.startSpeaking(_:)))
        menu.addItem("Stop Speaking", #selector(NSTextView.stopSpeaking(_:)))
        return menu
    }

    // MARK: - Format

    private static func formatMenu() -> NSMenu {
        let menu = NSMenu(title: "Format")
        let groups: [[MarkdownAction]] = [
            [.bold, .italic, .strikethrough],
            [],  // Heading submenu
            [.bulletList, .numberedList, .taskList, .quote],
            [.inlineCode, .codeBlock],
            [.link, .image, .table, .horizontalRule],
        ]
        for (index, group) in groups.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            if group.isEmpty {
                let headings = NSMenu(title: "Heading")
                MarkdownAction.headings.forEach { headings.addItem($0.menuItem()) }
                menu.addItem(submenu: headings)
            }
            group.forEach { menu.addItem($0.menuItem()) }
        }
        menu.addItem(.separator())
        let editorOnly: NSEvent.ModifierFlags = [.command, .control]
        menu.addItem("Bigger", #selector(AppDelegate.makeTextBigger(_:)), "=", editorOnly)
        menu.addItem("Smaller", #selector(AppDelegate.makeTextSmaller(_:)), "-", editorOnly)
        menu.addItem("Default Size", #selector(AppDelegate.resetTextSize(_:)), "0", editorOnly)
        return menu
    }

    // MARK: - View

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        let setLayout = #selector(DocumentWindowController.setPreviewLayout(_:))
        for (index, layout) in PreviewLayout.allCases.enumerated() {
            menu.addItem(layout.title, setLayout).tag = index
        }
        menu.addItem("Cycle Layout", #selector(DocumentWindowController.cyclePreviewLayout(_:)), "p", [.command, .option])
        menu.addItem(.separator())
        menu.addItem("Treat as Markdown", #selector(DocumentWindowController.toggleTreatAsMarkdown(_:)))
        menu.addItem(.separator())
        menu.addItem("Show Line Numbers", #selector(AppDelegate.toggleLineNumbers(_:)))
        menu.addItem("Show Indentation Guides", #selector(AppDelegate.toggleIndentGuides(_:)))
        menu.addItem(.separator())
        menu.addItem("Zoom In", #selector(AppDelegate.zoomIn(_:)), "+")
        // ⌘= (no Shift) is what people actually press for ⌘+.
        let equals = menu.addItem("Zoom In", #selector(AppDelegate.zoomIn(_:)), "=")
        equals.isHidden = true
        equals.allowsKeyEquivalentWhenHidden = true
        menu.addItem("Zoom Out", #selector(AppDelegate.zoomOut(_:)), "-")
        menu.addItem("Actual Size", #selector(AppDelegate.zoomToActualSize(_:)), "0")
        menu.addItem(submenu: previewZoomMenu())
        menu.addItem(.separator())
        menu.addItem("Show Toolbar", #selector(NSWindow.toggleToolbarShown(_:)))
        menu.addItem("Customize Toolbar…", #selector(NSWindow.runToolbarCustomizationPalette(_:)))
        menu.addItem(.separator())
        menu.addItem("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        return menu
    }

    /// Zooms just the preview; View ▸ Zoom In/Out moves both panes together.
    private static func previewZoomMenu() -> NSMenu {
        let menu = NSMenu(title: "Preview Zoom")
        let previewOnly: NSEvent.ModifierFlags = [.command, .option]
        menu.addItem("Zoom In", #selector(AppDelegate.previewZoomIn(_:)), "=", previewOnly)
        menu.addItem("Zoom Out", #selector(AppDelegate.previewZoomOut(_:)), "-", previewOnly)
        menu.addItem("Actual Size", #selector(AppDelegate.previewZoomToActualSize(_:)), "0", previewOnly)
        menu.addItem(.separator())
        menu.addItem("Scale to Window", #selector(AppDelegate.toggleScalePreviewToWindow(_:)))
        return menu
    }

    // MARK: - Window

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        menu.addItem("Zoom", #selector(NSWindow.performZoom(_:)))
        menu.addItem(.separator())
        menu.addItem("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        return menu
    }
}

extension NSMenu {
    /// Adds an item targeting the first responder. An uppercase key implies Shift.
    @discardableResult
    func addItem(_ title: String, _ action: Selector?, _ key: String = "",
                 _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        addItem(item)
        return item
    }

    @discardableResult
    func addItem(submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
        return item
    }
}
