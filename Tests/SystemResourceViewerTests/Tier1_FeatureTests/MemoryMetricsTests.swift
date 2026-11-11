import XCTest
@testable import SystemResourceViewer

final class MemoryMetricsTests: XCTestCase {

    func testMemoryMetricsInitializationDefaultEmpty() {
        let metrics = MemoryMetrics.empty
        XCTAssertEqual(metrics.totalBytes, 0)
        XCTAssertEqual(metrics.appMemoryBytes, 0)
        XCTAssertEqual(metrics.wiredBytes, 0)
        XCTAssertEqual(metrics.compressedBytes, 0)
        XCTAssertEqual(metrics.freeBytes, 0)
        XCTAssertEqual(metrics.usedBytes, 0)
        XCTAssertEqual(metrics.usedPercentage, 0.0)
        XCTAssertEqual(metrics.pressureLevel, .normal)
        XCTAssertTrue(metrics.topProcesses.isEmpty)
    }

    func testMemoryMetricsUsedBytesCalculation() {
        let metrics = MemoryMetrics(
            totalBytes: 16 * 1024 * 1024 * 1024,
            appMemoryBytes: 4 * 1024 * 1024 * 1024,
            wiredBytes: 2 * 1024 * 1024 * 1024,
            compressedBytes: 1 * 1024 * 1024 * 1024,
            cachedBytes: 3 * 1024 * 1024 * 1024,
            freeBytes: 6 * 1024 * 1024 * 1024
        )
        // 4 + 2 + 1 = 7 GB
        let expectedUsed: UInt64 = 7 * 1024 * 1024 * 1024
        XCTAssertEqual(metrics.usedBytes, expectedUsed)
    }

    func testMemoryMetricsUsedPercentage() {
        let total: UInt64 = 100 * 1024 * 1024
        let metrics = MemoryMetrics(
            totalBytes: total,
            appMemoryBytes: 25 * 1024 * 1024,
            wiredBytes: 15 * 1024 * 1024,
            compressedBytes: 10 * 1024 * 1024
        )
        // Used = 50 MB / 100 MB = 50.0%
        XCTAssertEqual(metrics.usedPercentage, 50.0, accuracy: 0.01)
    }

    func testMemoryPressureLevelSymbols() {
        XCTAssertEqual(MemoryPressureLevel.normal.systemSymbolName, "checkmark.circle.fill")
        XCTAssertEqual(MemoryPressureLevel.warning.systemSymbolName, "exclamationmark.triangle.fill")
        XCTAssertEqual(MemoryPressureLevel.critical.systemSymbolName, "xmark.octagon.fill")
        XCTAssertEqual(MemoryPressureLevel.normal.rawValue, "Normal")
        XCTAssertEqual(MemoryPressureLevel.warning.rawValue, "Warning")
        XCTAssertEqual(MemoryPressureLevel.critical.rawValue, "Critical")
    }

    func testMemoryMonitorServiceLivePoll() async {
        let service = MemoryMonitorService()
        let metrics = await service.pollMemoryMetrics(topProcesses: [])
        XCTAssertGreaterThan(metrics.totalBytes, 1024 * 1024 * 1024) // > 1 GB
        XCTAssertGreaterThan(metrics.usedBytes, 0)
        XCTAssertGreaterThanOrEqual(metrics.usedPercentage, 0.0)
        XCTAssertLessThanOrEqual(metrics.usedPercentage, 100.0)
    }

    func testDarwinMachBridgeVMStatistics() {
        guard let stats = DarwinMachBridge.fetchVMStatistics() else {
            XCTFail("Failed to fetch Darwin VM statistics")
            return
        }
        XCTAssertGreaterThan(stats.totalPhysicalBytes, 0)
        XCTAssertGreaterThan(stats.appBytes + stats.wiredBytes + stats.freeBytes, 0)
    }
}
