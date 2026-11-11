import XCTest
@testable import SystemResourceViewer

final class NetworkBoundaryTests: XCTestCase {

    func testZeroSpeedFormatting() {
        XCTAssertEqual(Formatters.formatSpeed(0.0), "0 B/s")
    }

    func testNilLatencyFallback() {
        let metrics = NetworkMetrics(latencyMilliseconds: nil)
        XCTAssertNil(metrics.latencyMilliseconds)
        XCTAssertEqual(Formatters.formatLatency(metrics.latencyMilliseconds), "—")
    }

    func testSubKilobyteSpeedFormatting() {
        XCTAssertEqual(Formatters.formatSpeed(1.0), "1 B/s")
        XCTAssertEqual(Formatters.formatSpeed(1023.0), "1023 B/s")
    }

    func testExtremeBandwidthFormatting() {
        let extremeSpeed = 150.0 * 1024.0 * 1024.0 * 1024.0 // 150 GB/s
        XCTAssertEqual(Formatters.formatSpeed(extremeSpeed), "150.0 GB/s")
    }

    func testDisconnectedStateHandling() {
        let offline = NetworkMetrics(
            primaryInterfaceName: "none",
            interfaceType: .disconnected,
            localIPv4: "—",
            latencyMilliseconds: nil
        )
        XCTAssertEqual(offline.interfaceType, .disconnected)
        XCTAssertEqual(offline.localIPv4, "—")
        XCTAssertNil(offline.latencyMilliseconds)
        XCTAssertEqual(offline.interfaceType.systemSymbolName, "wifi.slash")
    }
}
