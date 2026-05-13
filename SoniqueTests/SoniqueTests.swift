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

    @MainActor
    func testCheckNetworkConnectionPayloadValues() {
        XCTAssertEqual(NetworkMonitor.Connection.cellular.checkNetworkValue, "cellular")
        XCTAssertEqual(NetworkMonitor.Connection.wifi.checkNetworkValue, "wifi")
        XCTAssertEqual(NetworkMonitor.Connection.wired.checkNetworkValue, "ethernet")
        XCTAssertEqual(NetworkMonitor.Connection.other.checkNetworkValue, "unknown")
        XCTAssertEqual(NetworkMonitor.Connection.none.checkNetworkValue, "unknown")
    }
}
