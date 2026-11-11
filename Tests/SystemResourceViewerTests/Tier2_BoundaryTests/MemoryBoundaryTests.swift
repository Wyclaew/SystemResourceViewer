import XCTest
@testable import SystemResourceViewer

final class MemoryBoundaryTests: XCTestCase {

    func testZeroTotalBytesDivByZeroProtection() {
        let metrics = MemoryMetrics(
            totalBytes: 0,
            appMemoryBytes: 1024,
            wiredBytes: 2048,
            compressedBytes: 512
        )
        // Must return 0.0 without crash
        XCTAssertEqual(metrics.usedPercentage, 0.0)
    }

    func testOneHundredPercentMemorySaturation() {
        let total: UInt64 = 8 * 1024 * 1024 * 1024
        let metrics = MemoryMetrics(
            totalBytes: total,
            appMemoryBytes: 4 * 1024 * 1024 * 1024,
            wiredBytes: 3 * 1024 * 1024 * 1024,
            compressedBytes: 1 * 1024 * 1024 * 1024,
            freeBytes: 0
        )
        XCTAssertEqual(metrics.usedBytes, total)
        XCTAssertEqual(metrics.usedPercentage, 100.0, accuracy: 0.01)
    }

    func testOversubscribedMemoryClamping() {
        let total: UInt64 = 4 * 1024 * 1024 * 1024
        let metrics = MemoryMetrics(
            totalBytes: total,
            appMemoryBytes: 3 * 1024 * 1024 * 1024,
            wiredBytes: 2 * 1024 * 1024 * 1024,
            compressedBytes: 1 * 1024 * 1024 * 1024 // 6 GB used on 4 GB physical (e.g. heavy compression/swap)
        )
        // Clamped at 100.0%
        XCTAssertEqual(metrics.usedPercentage, 100.0)
    }

    func testZeroSwapAllocationHandling() {
        let metrics = MemoryMetrics(
            totalBytes: 16 * 1024 * 1024 * 1024,
            swapUsedBytes: 0,
            swapTotalBytes: 0
        )
        XCTAssertEqual(metrics.swapUsedBytes, 0)
        XCTAssertEqual(metrics.swapTotalBytes, 0)
    }

    func testAllMemoryPressureTransitions() {
        let normal = MemoryMetrics(pressureLevel: .normal)
        let warning = MemoryMetrics(pressureLevel: .warning)
        let critical = MemoryMetrics(pressureLevel: .critical)

        XCTAssertEqual(normal.pressureLevel.rawValue, "Normal")
        XCTAssertEqual(warning.pressureLevel.rawValue, "Warning")
        XCTAssertEqual(critical.pressureLevel.rawValue, "Critical")
    }
}
