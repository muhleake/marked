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
}
