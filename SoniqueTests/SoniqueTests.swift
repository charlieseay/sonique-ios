import XCTest
@testable import Sonique

final class SoniqueTests: XCTestCase {
    func testServerURLNormalization() {
        let s = SoniqueSettings()
        s.serverURL = "http://192.168.0.221:3000/"
        XCTAssertEqual(s.normalizedServerURL, "http://192.168.0.221:3000")
    }

    func testIsConfigured() {
        let s = SoniqueSettings()
        s.serverURL = ""
        XCTAssertFalse(s.isConfigured)
        s.serverURL = "http://192.168.0.221:3000"
        XCTAssertTrue(s.isConfigured)
    }
}
