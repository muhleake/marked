import AppKit
import WebKit
import XCTest
@testable import Marked

@MainActor
final class PreviewTests: XCTestCase {
    private var tempDir: URL!
    private var opened: [NSDocument] = []

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkedPreviewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        Preferences.previewZoom = 1
        Preferences.scalePreviewToWindow = false
        for doc in opened { doc.close() }
        opened.removeAll()
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func openWindow(_ name: String, _ text: String) async throws -> DocumentWindowController {
        let url = tempDir.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        let (doc, _) = try await NSDocumentController.shared.openDocument(withContentsOf: url, display: true)
        opened.append(doc)
        return try XCTUnwrap(doc.windowControllers.first as? DocumentWindowController)
    }

    /// Polls an isolated-world expression until it equals `expected`.
    private func waitFor<T: Equatable>(_ preview: PreviewViewController, _ script: String, equals expected: T,
                                       timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        var last: Any?
        while Date() < deadline {
            last = try? await preview.evaluate(script)
            if let value = last as? T, value == expected { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for \(script) == \(expected); last value: \(String(describing: last))", file: file, line: line)
    }

    func testPreviewRendersDocument() async throws {
        let controller = try await openWindow("render.md", "# Hello\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n- [x] done\n\n~~gone~~ www.example.com")
        let preview = controller.splitController.previewController
        try await waitFor(preview, "return document.querySelector('#content h1')?.textContent ?? ''", equals: "Hello")
        try await waitFor(preview, "return document.querySelectorAll('#content table td').length", equals: 2)
        try await waitFor(preview, "return document.querySelector('#content input[type=checkbox]')?.checked ?? false", equals: true)
        try await waitFor(preview, "return document.querySelector('#content del')?.textContent ?? ''", equals: "gone")
        try await waitFor(preview, "return document.querySelector('#content a')?.getAttribute('href') ?? ''", equals: "http://www.example.com/")
    }

    func testPreviewUpdatesAfterEditWithoutReload() async throws {
        let controller = try await openWindow("live.md", "first")
        let preview = controller.splitController.previewController
        try await waitFor(preview, "return document.querySelector('#content p')?.textContent ?? ''", equals: "first")
        _ = try await preview.evaluate("window.__marker = 42; return 1")
        controller.markdownDocument?.textStorage.replaceCharacters(in: NSRange(location: 0, length: 5), with: "## second")
        try await waitFor(preview, "return document.querySelector('#content h2')?.textContent ?? ''", equals: "second")
        // Same page (no reload): the marker set in the isolated world survives.
        try await waitFor(preview, "return window.__marker ?? 0", equals: 42)
    }

    func testRelativeImageResolvesAgainstDocumentFolder() async throws {
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("img"), withIntermediateDirectories: true)
        // 1×1 PNG.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!
        try png.write(to: tempDir.appendingPathComponent("img/dot.png"))
        let controller = try await openWindow("pic.md", "![dot](img/dot.png)")
        let preview = controller.splitController.previewController
        let expected = tempDir.appendingPathComponent("img/dot.png").absoluteString
        try await waitFor(preview, "return document.querySelector('#content img')?.getAttribute('src') ?? ''", equals: expected)
        try await waitFor(preview, "const i = document.querySelector('#content img'); return i && i.complete ? i.naturalWidth : -1", equals: 1)
    }

    func testRemoteImagesAreBlocked() async throws {
        let controller = try await openWindow("remote.md", "![x](https://example.com/x.png)")
        let preview = controller.splitController.previewController
        try await waitFor(preview, "return document.querySelector('#content img') ? 1 : 0", equals: 1)
        try await Task.sleep(nanoseconds: 500_000_000)
        try await waitFor(preview, "const i = document.querySelector('#content img'); return i.complete && i.naturalWidth === 0", equals: true)
    }

    func testInlineHTMLInExistingFilesStillRenders() async throws {
        let controller = try await openWindow("styled.md", "<u>under</u> <mark>marked</mark> <span style=\"color: #e5484d\">red</span>")
        let preview = controller.splitController.previewController
        try await waitFor(preview, "return getComputedStyle(document.querySelector('#content u')).textDecorationLine", equals: "underline")
        try await waitFor(preview, "return document.querySelector('#content mark')?.textContent ?? ''", equals: "marked")
        try await waitFor(preview, "return getComputedStyle(document.querySelector('#content span')).color", equals: "rgb(229, 72, 77)")
    }

    func testPageScriptIsDisabled() async throws {
        let controller = try await openWindow("xss.md", "<img src=\"nope.png\" onerror=\"document.title='pwned'\">\n\n<details><summary>s</summary>d</details>")
        let preview = controller.splitController.previewController
        try await waitFor(preview, "return document.querySelector('#content details') ? 1 : 0", equals: 1)
        try await Task.sleep(nanoseconds: 300_000_000)
        try await waitFor(preview, "return document.title", equals: "")
    }

    func testLinkClicksOpenExternallyAndNeverNavigate() async throws {
        let controller = try await openWindow("links.md", "[x](https://apple.com)")
        let preview = controller.splitController.previewController
        try await waitFor(preview, "return document.querySelector('#content a') ? 1 : 0", equals: 1)
        var opened: [URL] = []
        preview.openExternally = { opened.append($0) }

        let external = URL(string: "https://apple.com/")!
        XCTAssertEqual(preview.policy(for: external, type: .linkActivated, isMainFrame: true), .cancel)
        XCTAssertEqual(opened, [external])

        let shell = Bundle.main.url(forResource: "preview", withExtension: "html")!
        let anchor = URL(string: shell.absoluteString + "#section")!
        XCTAssertEqual(preview.policy(for: anchor, type: .linkActivated, isMainFrame: true), .allow)
        XCTAssertEqual(preview.policy(for: external, type: .other, isMainFrame: true), .cancel)
        XCTAssertEqual(preview.policy(for: shell, type: .reload, isMainFrame: true), .cancel)
        XCTAssertEqual(opened.count, 1)

        // A real click goes through the navigation delegate.
        _ = try await preview.evaluate("document.querySelector('#content a').click(); return 1")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(opened.last, external)
        try await waitFor(preview, "return location.href", equals: shell.absoluteString)
    }

    func testLayoutCycleAndTxtTreatAsMarkdown() async throws {
        let md = try await openWindow("cycle.md", "# x")
        md.layout = .split
        md.cyclePreviewLayout(nil)
        XCTAssertEqual(md.layout, .editorOnly)
        XCTAssertFalse(md.splitController.previewController.isActive)
        md.cyclePreviewLayout(nil)
        XCTAssertEqual(md.layout, .previewOnly)
        XCTAssertTrue(md.splitController.splitViewItems[0].isCollapsed)
        md.cyclePreviewLayout(nil)
        XCTAssertEqual(md.layout, .split)

        let txt = try await openWindow("plain.txt", "# not a heading here")
        XCTAssertEqual(txt.layout, .editorOnly)
        txt.cyclePreviewLayout(nil)
        XCTAssertEqual(txt.layout, .editorOnly, "⌥⌘P does nothing in a plain .txt window")
        txt.toggleTreatAsMarkdown(nil)
        XCTAssertTrue(txt.treatsAsMarkdown)
        XCTAssertEqual(txt.layout, Preferences.defaultLayout)
        try await waitFor(txt.splitController.previewController, "return document.querySelector('#content h1')?.textContent ?? ''", equals: "not a heading here")
        XCTAssertEqual(txt.markdownDocument?.fileURL?.pathExtension, "txt")
        txt.toggleTreatAsMarkdown(nil)
        XCTAssertEqual(txt.layout, .editorOnly)
    }

    func testScrollSyncFollowsEditor() async throws {
        let text = (1...400).map { "## Heading \($0)\n\nParagraph \($0)." }.joined(separator: "\n\n")
        let controller = try await openWindow("long.md", text)
        controller.layout = .split
        let preview = controller.splitController.previewController
        try await waitFor(preview, "return document.querySelectorAll('#content h2').length", equals: 400)
        let editor = controller.splitController.editorController

        // Scroll the editor to roughly line 600 (heading 151 starts at line 601).
        let layoutManager = try XCTUnwrap(editor.textView.layoutManager)
        let charIndex = (editor.textView.string as NSString).range(of: "## Heading 151\n").location
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: charIndex + 1))
        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1), actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: editor.textView.textContainer!)
        editor.textView.scroll(NSPoint(x: 0, y: rect.minY + editor.textView.textContainerOrigin.y))
        // The top edge sits at the heading or the blank line just above it.
        XCTAssertEqual(editor.topVisibleSourceLine(), 600.5, accuracy: 1.0)

        // The preview's top should now be at heading 151.
        let deadline = Date().addingTimeInterval(3)
        var heading = ""
        while Date() < deadline {
            heading = (try? await preview.evaluate("""
                const hs = Array.from(document.querySelectorAll('#content h2'));
                const h = hs.find(h => h.getBoundingClientRect().bottom > 0);
                return h ? h.textContent : '';
                """) as? String) ?? ""
            if heading == "Heading 151" { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(heading, "Heading 151")
    }

    // MARK: - Preview → editor scroll sync

    private func openLongDocument(_ name: String) async throws -> DocumentWindowController {
        let text = (1...400).map { "## Heading \($0)\n\nParagraph \($0)." }.joined(separator: "\n\n")
        let controller = try await openWindow(name, text)
        controller.layout = .split
        try await waitFor(controller.splitController.previewController,
                          "return document.querySelectorAll('#content h2').length", equals: 400)
        // Let the quiet period after the render pass, as it would for a person.
        try await Task.sleep(nanoseconds: 400_000_000)
        return controller
    }

    private func waitForEditorLine(_ editor: EditorViewController, near line: Double, accuracy: Double = 2,
                                   file: StaticString = #filePath, lineNumber: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(3)
        var top = 0.0
        while Date() < deadline {
            top = editor.topVisibleSourceLine()
            if abs(top - line) <= accuracy { return }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        XCTFail("editor stayed at line \(top), expected about \(line)", file: file, line: lineNumber)
    }

    func testPreviewScrollMovesEditor() async throws {
        let controller = try await openLongDocument("back.md")
        let preview = controller.splitController.previewController
        let editor = controller.splitController.editorController

        // Heading 151 starts at source line 601.
        _ = try await preview.evaluate("""
            const h = Array.from(document.querySelectorAll('#content h2'))[150];
            window.scrollTo(0, h.getBoundingClientRect().top + window.scrollY - 8);
            return 1;
            """)
        try await waitForEditorLine(editor, near: 601)

        // The editor's own scroll must not bounce back and move the preview.
        let before = try await preview.evaluate("return window.scrollY") as? Double
        try await Task.sleep(nanoseconds: 500_000_000)
        let after = try await preview.evaluate("return window.scrollY") as? Double
        XCTAssertEqual(before, after)
    }

    func testPreviewScrollToEndReachesEditorEnd() async throws {
        let controller = try await openLongDocument("end.md")
        let preview = controller.splitController.previewController
        let editor = controller.splitController.editorController
        _ = try await preview.evaluate("window.scrollTo(0, document.documentElement.scrollHeight); return 1")
        let deadline = Date().addingTimeInterval(3)
        while editor.topVisibleSourceLine() < 1000, Date() < deadline { try await Task.sleep(nanoseconds: 30_000_000) }
        XCTAssertGreaterThan(editor.topVisibleSourceLine(), 1000, "the last line is about 1,199")
    }

    func testPreviewBackToTopReachesEditorTop() async throws {
        let controller = try await openLongDocument("top.md")
        let preview = controller.splitController.previewController
        let editor = controller.splitController.editorController
        _ = try await preview.evaluate("window.scrollTo(0, 5000); return 1")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertGreaterThan(editor.topVisibleSourceLine(), 10)
        _ = try await preview.evaluate("window.scrollTo(0, 0); return 1")
        try await waitForEditorLine(editor, near: 1, accuracy: 0.5)
    }

    func testPreviewReUpdateWhileTypingDoesNotMoveEditor() async throws {
        let controller = try await openLongDocument("typing.md")
        let preview = controller.splitController.previewController
        let editor = controller.splitController.editorController
        _ = try await preview.evaluate("window.scrollTo(0, 3000); return 1")
        try await Task.sleep(nanoseconds: 300_000_000)
        let settled = editor.topVisibleSourceLine()

        // A render replaces the page; that isn't the user scrolling.
        let storage = try XCTUnwrap(controller.markdownDocument?.textStorage)
        storage.replaceCharacters(in: NSRange(location: storage.length, length: 0), with: "\n\nMore.")
        try await waitFor(preview, "return Array.from(document.querySelectorAll('#content p')).pop()?.textContent ?? ''", equals: "More.")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(editor.topVisibleSourceLine(), settled, accuracy: 0.01)
    }

    func testEditorOnlyIgnoresPreviewScroll() async throws {
        let controller = try await openLongDocument("hidden.md")
        controller.layout = .editorOnly
        controller.splitController.syncEditorScroll(toSourceLine: 500)
        XCTAssertLessThan(controller.splitController.editorController.topVisibleSourceLine(), 2)
    }

    // MARK: - Zoom

    func testPreviewZoomScalesAndReflows() async throws {
        let controller = try await openWindow("zoom.md", String(repeating: "A long line of words that has to wrap. ", count: 40))
        let preview = controller.splitController.previewController
        let webView = try XCTUnwrap(preview.webView)
        try await waitFor(preview, "return document.querySelector('#content p') ? 1 : 0", equals: 1)
        XCTAssertTrue(webView.allowsMagnification, "pinch to zoom")

        Preferences.previewZoom = 1.5
        XCTAssertEqual(webView.pageZoom, 1.5, accuracy: 0.001)
        // Text re-wraps instead of running off the side of the pane.
        try await waitFor(preview, "return document.documentElement.scrollWidth <= document.documentElement.clientWidth", equals: true)

        Preferences.previewZoom = 0.7
        XCTAssertEqual(webView.pageZoom, 0.7, accuracy: 0.001)

        webView.magnification = 2
        Preferences.previewZoom = 1
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
        XCTAssertEqual(webView.magnification, 1, "Actual Size also clears a pinch")
    }

    func testPreviewZoomStaysInRangeOnWholePercents() {
        Preferences.previewZoom = 1
        for _ in 0..<3 { Preferences.previewZoom += Preferences.previewZoomStep }
        XCTAssertEqual(Preferences.previewZoom, 1.3)
        Preferences.previewZoom = 99
        XCTAssertEqual(Preferences.previewZoom, Preferences.previewZoomRange.upperBound)
        Preferences.previewZoom = 0.01
        XCTAssertEqual(Preferences.previewZoom, Preferences.previewZoomRange.lowerBound)
    }

    func testScaleToWindowFollowsPaneWidth() async throws {
        let controller = try await openWindow("scale.md", "# x")
        controller.layout = .split
        let preview = controller.splitController.previewController
        let webView = try XCTUnwrap(preview.webView)
        Preferences.scalePreviewToWindow = true
        let expected = { Double(preview.view.bounds.width / PreviewViewController.scaleReferenceWidth).clamped(to: 0.5...1.5) }
        XCTAssertEqual(webView.pageZoom, expected(), accuracy: 0.01)

        let narrow = try XCTUnwrap(controller.window)
        narrow.setContentSize(NSSize(width: 700, height: 500))
        narrow.layoutIfNeeded()
        preview.view.layoutSubtreeIfNeeded()
        preview.viewDidLayout()
        XCTAssertLessThan(preview.view.bounds.width, 640)
        XCTAssertEqual(webView.pageZoom, expected(), accuracy: 0.01)

        Preferences.scalePreviewToWindow = false
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
    }

    func testViewZoomMovesBothPanesAndPreviewZoomOnlyPreview() async throws {
        let savedSize = Preferences.editorFontSize
        defer { Preferences.editorFontSize = savedSize }
        Preferences.editorFontSize = 13
        let app = try XCTUnwrap(NSApp.delegate as? AppDelegate)

        app.zoomIn(nil)
        XCTAssertEqual(Preferences.editorFontSize, 14)
        XCTAssertEqual(Preferences.previewZoom, 1.1)
        app.previewZoomIn(nil)
        XCTAssertEqual(Preferences.editorFontSize, 14)
        XCTAssertEqual(Preferences.previewZoom, 1.2)
        app.zoomToActualSize(nil)
        XCTAssertEqual(Preferences.editorFontSize, 13)
        XCTAssertEqual(Preferences.previewZoom, 1)
    }

    func testZoomMenuItemsDisableAtLimits() throws {
        let app = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        let view = try XCTUnwrap(NSApp.mainMenu?.item(withTitle: "View")?.submenu)
        let zoomMenu = try XCTUnwrap(view.item(withTitle: "Preview Zoom")?.submenu)
        let zoomIn = try XCTUnwrap(zoomMenu.item(withTitle: "Zoom In"))
        let zoomOut = try XCTUnwrap(zoomMenu.item(withTitle: "Zoom Out"))
        let actual = try XCTUnwrap(zoomMenu.item(withTitle: "Actual Size"))
        let scale = try XCTUnwrap(zoomMenu.item(withTitle: "Scale to Window"))

        XCTAssertFalse(app.validateMenuItem(actual), "already at 100%")
        Preferences.previewZoom = Preferences.previewZoomRange.upperBound
        XCTAssertFalse(app.validateMenuItem(zoomIn))
        XCTAssertTrue(app.validateMenuItem(actual))
        Preferences.previewZoom = Preferences.previewZoomRange.lowerBound
        XCTAssertFalse(app.validateMenuItem(zoomOut))

        XCTAssertTrue(app.validateMenuItem(scale))
        XCTAssertEqual(scale.state, .off)
        app.toggleScalePreviewToWindow(nil)
        _ = app.validateMenuItem(scale)
        XCTAssertEqual(scale.state, .on)
    }

    func testLargeDocumentRenderAndUpdateTiming() async throws {
        let controller = try await openWindow("big.md", RendererTests.largeDocument(lines: 5000))
        controller.layout = .split
        let preview = controller.splitController.previewController
        try await waitFor(preview, "return document.querySelectorAll('#content h2').length > 200", equals: true, timeout: 10)

        var renderTimes: [TimeInterval] = []
        preview.onRender = { renderTimes.append($0) }
        let storage = try XCTUnwrap(controller.markdownDocument?.textStorage)

        // Main-thread cost of one edit (what a keystroke pays before the debounce).
        let start = CFAbsoluteTimeGetCurrent()
        storage.replaceCharacters(in: NSRange(location: storage.length, length: 0), with: "\n\nTyped paragraph.")
        let editCost = (CFAbsoluteTimeGetCurrent() - start) * 1000

        let updateStart = CFAbsoluteTimeGetCurrent()
        try await waitFor(preview, "return Array.from(document.querySelectorAll('#content p')).pop()?.textContent ?? ''",
                          equals: "Typed paragraph.", timeout: 10)
        let visibleAfter = (CFAbsoluteTimeGetCurrent() - updateStart) * 1000
        let render = (renderTimes.first ?? 0) * 1000
        print(String(format: "PREVIEW-5000: edit on main %.2f ms; cmark render %.1f ms; edit→visible %.0f ms (includes %.0f ms debounce)",
                     editCost, render, visibleAfter, PreviewViewController.debounceInterval * 1000))
        XCTAssertLessThan(editCost, 16, "an edit must not block the main thread for a frame")
        XCTAssertLessThan(render, 100)
    }
}
