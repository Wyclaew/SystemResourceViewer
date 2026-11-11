import XCTest
@testable import SystemResourceViewer

final class NetworkMetricsTests: XCTestCase {

    func testNetworkMetricsInitializationDefaultEmpty() {
        let metrics = NetworkMetrics.empty
        XCTAssertEqual(metrics.downloadBytesPerSecond, 0.0)
        XCTAssertEqual(metrics.uploadBytesPerSecond, 0.0)
        XCTAssertEqual(metrics.primaryInterfaceName, "en0")
        XCTAssertEqual(metrics.interfaceType, .disconnected)
        XCTAssertEqual(metrics.localIPv4, "—")
        XCTAssertNil(metrics.latencyMilliseconds)
    }

    func testNetworkInterfaceTypeSymbols() {
        XCTAssertEqual(NetworkInterfaceType.wifi.systemSymbolName, "wifi")
        XCTAssertEqual(NetworkInterfaceType.ethernet.systemSymbolName, "cable.connector")
        XCTAssertEqual(NetworkInterfaceType.cellular.systemSymbolName, "antenna.radiowaves.left.and.right")
        XCTAssertEqual(NetworkInterfaceType.loopback.systemSymbolName, "arrow.triangle.2.circlepath")
        XCTAssertEqual(NetworkInterfaceType.other.systemSymbolName, "network")
        XCTAssertEqual(NetworkInterfaceType.disconnected.systemSymbolName, "wifi.slash")
    }

    func testFormattersFormatSpeed() {
        XCTAssertEqual(Formatters.formatSpeed(500), "500 B/s")
        XCTAssertEqual(Formatters.formatSpeed(2048), "2 KB/s")
        XCTAssertEqual(Formatters.formatSpeed(5 * 1024 * 1024), "5.0 MB/s")
        XCTAssertEqual(Formatters.formatSpeed(2.5 * 1024 * 1024 * 1024), "2.5 GB/s")
    }

    func testFormattersFormatLatency() {
        XCTAssertEqual(Formatters.formatLatency(nil), "—")
        XCTAssertEqual(Formatters.formatLatency(15.4), "15 ms")
        XCTAssertEqual(Formatters.formatLatency(120.9), "121 ms")
    }

    func testNetworkMonitorServiceLivePoll() async {
        let service = NetworkMonitorService()
        let metrics = await service.pollNetworkMetrics()
        XCTAssertFalse(metrics.primaryInterfaceName.isEmpty)
        XCTAssertGreaterThanOrEqual(metrics.downloadBytesPerSecond, 0.0)
        XCTAssertGreaterThanOrEqual(metrics.uploadBytesPerSecond, 0.0)
    }
}
