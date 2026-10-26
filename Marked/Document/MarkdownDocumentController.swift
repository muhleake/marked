import AppKit

final class MarkdownDocumentController: NSDocumentController {
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown"]

    /// Maps Markdown extensions to the Markdown type even when the system resolves
    /// them to a dynamic type (e.g. `.mdown` before Marked is registered).
    override func typeForContents(of url: URL) throws -> String {
        if Self.markdownExtensions.contains(url.pathExtension.lowercased()) {
            return MarkdownDocument.markdownType
        }
        return try super.typeForContents(of: url)
    }

    // MARK: - State restoration

    private static var pendingRestorations = 0

    /// AppKit skips the untitled document when it restores state at launch. If every
    /// restored window fails (its file was deleted or moved), open one anyway, like
    /// a normal launch.
    override class func restoreWindow(withIdentifier identifier: NSUserInterfaceItemIdentifier,
                                      state: NSCoder,
                                      completionHandler: @escaping (NSWindow?, Error?) -> Void) {
        pendingRestorations += 1
        super.restoreWindow(withIdentifier: identifier, state: state) { window, error in
            completionHandler(window, error)
            pendingRestorations -= 1
            DispatchQueue.main.async {
                guard pendingRestorations == 0, shared.documents.isEmpty else { return }
                shared.newDocument(nil)
            }
        }
    }
}
