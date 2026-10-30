import AppKit

/// The document window's NSToolbar: Markdown actions plus the layout control.
/// Users can customize it (right-click ▸ Customize Toolbar).
final class ToolbarController: NSObject, NSToolbarDelegate {
    static let identifier = NSToolbar.Identifier("MarkedDocumentToolbar")
    static let headingItem = NSToolbarItem.Identifier("heading")
    static let layoutItem = NSToolbarItem.Identifier("layout")

    private weak var windowController: DocumentWindowController?
    private var layoutGroups: [NSToolbarItemGroup] = []

    init(windowController: DocumentWindowController) {
        self.windowController = windowController
        super.init()
    }

    func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: Self.identifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        return toolbar
    }

    static func identifier(for action: MarkdownAction) -> NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("md.\(action.rawValue)")
    }

    private static let buttonActions: [MarkdownAction] = [
        .bold, .italic, .strikethrough, .bulletList, .numberedList, .taskList, .quote,
        .inlineCode, .codeBlock, .link, .image, .table, .horizontalRule,
    ]

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        let id = Self.identifier(for:)
        return [
            id(.bold), id(.italic), id(.strikethrough), Self.headingItem, .space,
            id(.bulletList), id(.numberedList), id(.taskList), id(.quote), .space,
            id(.inlineCode), id(.codeBlock), id(.link), id(.image), id(.table), id(.horizontalRule),
            .flexibleSpace, Self.layoutItem,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.buttonActions.map(Self.identifier(for:)) + [Self.headingItem, Self.layoutItem, .space, .flexibleSpace]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if identifier == Self.headingItem { return headingItem() }
        if identifier == Self.layoutItem { return layoutItem() }
        guard let action = Self.buttonActions.first(where: { Self.identifier(for: $0) == identifier }) else { return nil }

        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = action.title
        item.paletteLabel = action.title
        item.toolTip = "\(action.title) (\(Self.shortcutDescription(action)))"
        item.image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: action.title)
        item.action = #selector(DocumentWindowController.applyMarkdownAction(_:))
        item.tag = action.rawValue
        item.isBordered = true
        item.autovalidates = true
        return item
    }

    private func headingItem() -> NSToolbarItem {
        let menu = NSMenu(title: "Heading")
        for action in MarkdownAction.headings {
            menu.addItem(action.menuItem())
        }
        let item = NSMenuToolbarItem(itemIdentifier: Self.headingItem)
        item.menu = menu
        item.showsIndicator = true
        item.label = "Heading"
        item.paletteLabel = "Heading"
        item.toolTip = "Heading (⌘1–⌘6)"
        item.image = NSImage(systemSymbolName: "number", accessibilityDescription: "Heading")
        item.isBordered = true
        return item
    }

    private func layoutItem() -> NSToolbarItem {
        let images = [("rectangle.split.2x1", "Split"), ("doc.plaintext", "Editor Only"), ("eye", "Preview Only")]
            .map { NSImage(systemSymbolName: $0.0, accessibilityDescription: $0.1)! }
        let group = NSToolbarItemGroup(itemIdentifier: Self.layoutItem, images: images, selectionMode: .selectOne,
                                       labels: PreviewLayout.allCases.map(\.title),
                                       target: self, action: #selector(layoutChanged(_:)))
        group.label = "Layout"
        group.paletteLabel = "Layout"
        group.toolTip = "Split / Editor / Preview (⌥⌘P)"
        group.controlRepresentation = .expanded
        layoutGroups.append(group)
        syncLayout()
        return group
    }

    @objc private func layoutChanged(_ sender: NSToolbarItemGroup) {
        guard let windowController, PreviewLayout.allCases.indices.contains(sender.selectedIndex) else { return }
        if windowController.isMarkdownEnabled {
            windowController.layout = PreviewLayout.allCases[sender.selectedIndex]
        }
        syncLayout()
    }

    /// Reflects the window's layout and Markdown mode in the segmented control.
    func syncLayout() {
        guard let windowController else { return }
        let index = PreviewLayout.allCases.firstIndex(of: windowController.layout) ?? 0
        for group in layoutGroups {
            group.selectedIndex = index
            group.isEnabled = windowController.isMarkdownEnabled
            for (i, sub) in group.subitems.enumerated() { sub.isEnabled = windowController.isMarkdownEnabled || i == index }
        }
    }

    static func shortcutDescription(_ action: MarkdownAction) -> String {
        let (key, modifiers) = action.shortcut
        var mods = modifiers
        var glyph = key.uppercased()
        let shifted: [String: String] = ["*": "8", "&": "7", ">": ".", "_": "-"]
        if let base = shifted[key] { glyph = base; mods.insert(.shift) }
        if key.count == 1, key != key.lowercased() { mods.insert(.shift) }
        var out = ""
        if mods.contains(.control) { out += "⌃" }
        if mods.contains(.option) { out += "⌥" }
        if mods.contains(.shift) { out += "⇧" }
        if mods.contains(.command) { out += "⌘" }
        return out + glyph
    }
}
