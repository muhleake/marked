import AppKit

enum PreviewLayout: String, CaseIterable {
    case split
    case editorOnly
    case previewOnly

    var title: String {
        switch self {
        case .split: "Split"
        case .editorOnly: "Editor Only"
        case .previewOnly: "Preview Only"
        }
    }

    var next: PreviewLayout {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// Editor on the left, preview on the right; either side can collapse.
final class SplitViewController: NSSplitViewController {
    let editorController: EditorViewController
    let previewController: NSViewController

    private lazy var editorItem = NSSplitViewItem(viewController: editorController)
    private lazy var previewItem = NSSplitViewItem(viewController: previewController)

    var layout: PreviewLayout = .split {
        didSet { applyLayout() }
    }

    init(document: MarkdownDocument) {
        editorController = EditorViewController(textStorage: document.textStorage)
        previewController = PreviewPlaceholderViewController()
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        editorItem.canCollapse = true
        editorItem.minimumThickness = 220
        editorItem.holdingPriority = .defaultLow
        previewItem.canCollapse = true
        previewItem.minimumThickness = 220
        previewItem.holdingPriority = .defaultLow

        addSplitViewItem(editorItem)
        addSplitViewItem(previewItem)
        applyLayout()
    }

    private func applyLayout() {
        guard isViewLoaded else { return }
        editorItem.isCollapsed = layout == .previewOnly
        previewItem.isCollapsed = layout == .editorOnly
    }

    var isPreviewVisible: Bool { layout != .editorOnly }
}

/// Empty right-hand pane until the live preview exists.
final class PreviewPlaceholderViewController: NSViewController {
    override func loadView() {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        self.view = view
    }
}
