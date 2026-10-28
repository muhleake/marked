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

    func testUnderlineHighlightAndColorRender() async throws {
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
