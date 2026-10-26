import XCTest
@testable import Marked

final class ScaffoldTests: XCTestCase {
    func testBundleIdentifier() {
        XCTAssertEqual(Bundle(for: AppDelegate.self).bundleIdentifier, "io.github.muhleake.marked")
    }
}
