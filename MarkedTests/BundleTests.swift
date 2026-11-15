import XCTest
@testable import Marked

final class BundleTests: XCTestCase {
    func testBundleIdentifier() {
        XCTAssertEqual(Bundle(for: AppDelegate.self).bundleIdentifier, "io.github.muhleake.marked")
    }

    func testAppIconIsBundled() {
        let bundle = Bundle(for: AppDelegate.self)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String, "AppIcon")
        XCTAssertNotNil(bundle.url(forResource: "AppIcon", withExtension: "icns"))
    }

    func testQuickLookExtensionIsEmbeddedForMarkdown() throws {
        let app = Bundle(for: AppDelegate.self)
        let url = try XCTUnwrap(app.builtInPlugInsURL?.appendingPathComponent("MarkedQuickLook.appex"))
        let appex = try XCTUnwrap(Bundle(url: url))
        XCTAssertEqual(appex.bundleIdentifier, "io.github.muhleake.marked.quicklook")
        XCTAssertEqual(appex.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                       app.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        let ext = try XCTUnwrap(appex.object(forInfoDictionaryKey: "NSExtension") as? [String: Any])
        XCTAssertEqual(ext["NSExtensionPointIdentifier"] as? String, "com.apple.quicklook.preview")
        let attributes = try XCTUnwrap(ext["NSExtensionAttributes"] as? [String: Any])
        XCTAssertEqual(attributes["QLIsDataBasedPreview"] as? Bool, true)
        XCTAssertEqual(Set(attributes["QLSupportedContentTypes"] as? [String] ?? []),
                       ["net.daringfireball.markdown", "io.github.muhleake.marked.mdown"])
        XCTAssertNotNil(appex.url(forResource: "preview", withExtension: "css"))
    }
}
