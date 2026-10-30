import AppKit
import PDFKit
import XCTest
@testable import Marked

@MainActor
final class AppFeaturesTests: XCTestCase {
    private var tempDir: URL!
    private var opened: [NSDocument] = []

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkedAppFeaturesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        opened.forEach { $0.close() }
        opened.removeAll()
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func open(_ name: String, _ text: String, display: Bool = true) async throws -> (MarkdownDocument, DocumentWindowController?) {
        let url = tempDir.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        let (doc, _) = try await NSDocumentController.shared.openDocument(withContentsOf: url, display: display)
        opened.append(doc)
        let markdown = try XCTUnwrap(doc as? MarkdownDocument)
        return (markdown, markdown.windowControllers.first as? DocumentWindowController)
    }

    private func exportPDF(_ doc: MarkdownDocument, name: String) async throws -> PDFDocument {
        let url = tempDir.appendingPathComponent(name)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            doc.exportPDF(to: url) { error in if let error { cont.resume(throwing: error) } else { cont.resume() } }
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        return try XCTUnwrap(PDFDocument(url: url), "no PDF written")
    }

    // MARK: - Print / PDF

    func testExportPDFPrintsRenderedMarkdown() async throws {
        let (doc, _) = try await open("print.md", "# Printed Title\n\nSome **bold** text.\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n- [x] task")
        let pdf = try await exportPDF(doc, name: "print.pdf")
        let text = pdf.string ?? ""
        XCTAssertGreaterThanOrEqual(pdf.pageCount, 1)
        XCTAssertTrue(text.contains("Printed Title"), text)
        XCTAssertTrue(text.contains("Some bold text."), text)
        XCTAssertFalse(text.contains("**"), "printed the raw Markdown instead of the preview")
        XCTAssertFalse(text.contains("# Printed"), "printed the raw Markdown instead of the preview")
    }

    func testExportPDFPaginatesLongDocuments() async throws {
        let (doc, _) = try await open("long.md", RendererTests.largeDocument(lines: 1500))
        let pdf = try await exportPDF(doc, name: "long.pdf")
        print("PDF-1500: \(pdf.pageCount) pages")
        XCTAssertGreaterThan(pdf.pageCount, 5)
    }

    func testExportPlainTextPrintsRawText() async throws {
        let (doc, _) = try await open("raw.txt", "# not a heading\n**literal**")
        let pdf = try await exportPDF(doc, name: "raw.pdf")
        let text = pdf.string ?? ""
        XCTAssertTrue(text.contains("# not a heading"), text)
        XCTAssertTrue(text.contains("**literal**"), text)
    }

    func testPrintOperationUsesDocumentPrintInfo() async throws {
        let (doc, _) = try await open("op.md", "# Op")
        doc.printInfo.orientation = .landscape
        let operation: NSPrintOperation? = await withCheckedContinuation { cont in
            PreviewPrinter.makePrintOperation(for: doc, markdown: true, printInfo: doc.printInfo) { cont.resume(returning: $0) }
        }
        let op = try XCTUnwrap(operation)
        XCTAssertNotNil(op.view)
        XCTAssertGreaterThan(op.view?.frame.width ?? 0, 0)
        XCTAssertEqual(op.printInfo.orientation, .landscape)
        XCTAssertEqual(op.jobTitle, doc.displayName)
    }

    // MARK: - Copy as HTML

    func testCopyAsHTMLWholeDocumentAndSelection() async throws {
        let (_, controller) = try await open("copy.md", "# Head\n\n**bold** line")
        let wc = try XCTUnwrap(controller)
        let textView = try XCTUnwrap(wc.editorTextView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        wc.copyAsHTML(nil)
        XCTAssertEqual(NSPasteboard.general.string(forType: .html), "<h1>Head</h1>\n<p><strong>bold</strong> line</p>\n")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "<h1>Head</h1>\n<p><strong>bold</strong> line</p>\n")

        textView.setSelectedRange(NSRange(location: 8, length: 8))
        wc.copyAsHTML(nil)
        XCTAssertEqual(NSPasteboard.general.string(forType: .html), "<p><strong>bold</strong></p>\n")
    }

    // MARK: - External changes

    private func writeFromAnotherProcess(_ text: String, to url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf '%s' \"$1\" > \"$2\"", "sh", text, url.path]
        try process.run()
        process.waitUntilExit()
    }

    func testExternalEditPromptsAndReloads() async throws {
        let (doc, _) = try await open("ext.md", "original")
        var asked = 0
        doc.askToReload = { _, answer in asked += 1; answer(true) }
        try await Task.sleep(nanoseconds: 1_100_000_000)  // distinct modification time
        try writeFromAnotherProcess("changed elsewhere", to: doc.fileURL!)

        let deadline = Date().addingTimeInterval(8)
        while doc.text != "changed elsewhere", Date() < deadline { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertEqual(asked, 1, "the file presenter should notice the change and ask once")
        XCTAssertEqual(doc.text, "changed elsewhere")
        XCTAssertFalse(doc.isDocumentEdited)
    }

    func testKeepThisVersionDoesNotReload() async throws {
        let (doc, _) = try await open("keep.md", "mine")
        var asked = 0
        doc.askToReload = { _, answer in asked += 1; answer(false) }
        try await Task.sleep(nanoseconds: 1_100_000_000)
        try writeFromAnotherProcess("theirs", to: doc.fileURL!)
        doc.checkForExternalChange()
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(doc.text, "mine")
        // A second check with nothing new doesn't ask again.
        doc.checkForExternalChange()
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(asked, 1)
    }

    func testIdenticalContentDoesNotPrompt() async throws {
        let (doc, _) = try await open("same.md", "same")
        doc.askToReload = { _, _ in XCTFail("should not ask when contents are identical") }
        try await Task.sleep(nanoseconds: 1_100_000_000)
        try writeFromAnotherProcess("same", to: doc.fileURL!)
        doc.checkForExternalChange()
        try await Task.sleep(nanoseconds: 500_000_000)
    }

    // MARK: - State restoration

    func testWindowLayoutRoundTripsThroughRestorableState() async throws {
        let (_, controller) = try await open("restore.md", "# r")
        let wc = try XCTUnwrap(controller)
        wc.layout = .previewOnly
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        wc.window(wc.window!, willEncodeRestorableState: archiver)
        archiver.finishEncoding()

        let (_, other) = try await open("restore2.md", "# r2")
        let target = try XCTUnwrap(other)
        XCTAssertEqual(target.layout, Preferences.defaultLayout)
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        target.window(target.window!, didDecodeRestorableState: unarchiver)
        XCTAssertEqual(target.layout, .previewOnly)
    }

    func testTreatAsMarkdownRoundTripsThroughRestorableState() async throws {
        let (_, controller) = try await open("restore.txt", "# t")
        let wc = try XCTUnwrap(controller)
        wc.toggleTreatAsMarkdown(nil)
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        wc.window(wc.window!, willEncodeRestorableState: archiver)
        archiver.finishEncoding()

        let (_, other) = try await open("restore2.txt", "# t2")
        let target = try XCTUnwrap(other)
        XCTAssertFalse(target.treatsAsMarkdown)
        target.window(target.window!, didDecodeRestorableState: try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData))
        XCTAssertTrue(target.treatsAsMarkdown)
        XCTAssertEqual(target.layout, Preferences.defaultLayout)
    }

    func testDocumentWindowsAreRestorable() async throws {
        let (_, controller) = try await open("r.md", "x")
        XCTAssertTrue(controller?.window?.isRestorable ?? false)
        XCTAssertTrue(MarkdownDocument.autosavesInPlace, "untitled and unsaved edits come back after relaunch")
    }

    // MARK: - Settings

    func testSettingsWindowControlsWritePreferences() async throws {
        let savedSize = Preferences.editorFontSize, savedLayout = Preferences.defaultLayout, savedTheme = Preferences.previewTheme
        defer {
            Preferences.editorFontSize = savedSize
            Preferences.defaultLayout = savedLayout
            Preferences.previewTheme = savedTheme
            Preferences.previewZoom = 1
            Preferences.scalePreviewToWindow = false
        }

        let settings = SettingsWindowController.shared
        settings.showWindow(nil)
        let controls = settings.controls
        controls.stepper.integerValue = 17
        settings.sizeStepperChanged(controls.stepper)
        XCTAssertEqual(Preferences.editorFontSize, 17)
        XCTAssertEqual(controls.size.integerValue, 17)

        controls.zoom.doubleValue = 1.4
        settings.zoomStepperChanged(controls.zoom)
        XCTAssertEqual(Preferences.previewZoom, 1.4)
        XCTAssertEqual(controls.zoomLabel.stringValue, "140%")
        controls.scale.state = .on
        settings.scaleCheckboxChanged(controls.scale)
        XCTAssertTrue(Preferences.scalePreviewToWindow)

        controls.layout.selectItem(at: 1)
        settings.layoutChanged(controls.layout)
        XCTAssertEqual(Preferences.defaultLayout, .editorOnly)

        let (_, controller) = try await open("theme.md", "x")
        let webView = try XCTUnwrap(controller?.splitController.previewController.webView)
        XCTAssertNil(webView.appearance, "follows the system by default")
        controls.theme.selectItem(at: 2)
        settings.themeChanged(controls.theme)
        XCTAssertEqual(webView.appearance?.name, .darkAqua)
        settings.close()
    }

    func testFindBarAndFindReplaceOpen() async throws {
        let (_, controller) = try await open("find.md", "find me, find me")
        let wc = try XCTUnwrap(controller)
        let textView = try XCTUnwrap(wc.editorTextView)
        let scrollView = try XCTUnwrap(wc.splitController.editorController.scrollView)
        let find = NSMenuItem(); find.tag = NSTextFinder.Action.showFindInterface.rawValue
        textView.performTextFinderAction(find)
        XCTAssertTrue(scrollView.isFindBarVisible, "⌘F shows the find bar")
        let replace = NSMenuItem(); replace.tag = NSTextFinder.Action.showReplaceInterface.rawValue
        textView.performTextFinderAction(replace)
        XCTAssertTrue(scrollView.isFindBarVisible, "⌥⌘F shows find & replace")
    }

    func testMenusHaveFinishItems() throws {
        let file = try XCTUnwrap(NSApp.mainMenu?.item(withTitle: "File")?.submenu)
        XCTAssertEqual(file.item(withTitle: "Export as PDF…")?.action, #selector(NSDocument.saveToPDF(_:)))
        XCTAssertNotNil(file.item(withTitle: "Page Setup…"))
        let edit = try XCTUnwrap(NSApp.mainMenu?.item(withTitle: "Edit")?.submenu)
        XCTAssertEqual(edit.item(withTitle: "Copy as HTML")?.action, #selector(DocumentWindowController.copyAsHTML(_:)))
        let app = try XCTUnwrap(NSApp.mainMenu?.items.first?.submenu)
        XCTAssertEqual(app.item(withTitle: "Settings…")?.keyEquivalent, ",")
    }
}
