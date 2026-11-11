import XCTest
@testable import SystemResourceViewer

final class DiskMetricsTests: XCTestCase {

    func testDiskMetricsInitializationDefaultEmpty() {
        let metrics = DiskMetrics.empty
        XCTAssertEqual(metrics.volumeName, "Macintosh HD")
        XCTAssertEqual(metrics.totalBytes, 0)
        XCTAssertEqual(metrics.freeBytes, 0)
        XCTAssertEqual(metrics.readBytesPerSecond, 0.0)
        XCTAssertEqual(metrics.writeBytesPerSecond, 0.0)
        XCTAssertEqual(metrics.usedBytes, 0)
        XCTAssertEqual(metrics.usedPercentage, 0.0)
    }

    func testDiskMetricsUsedBytes() {
        let total: UInt64 = 500 * 1024 * 1024 * 1024
        let free: UInt64 = 200 * 1024 * 1024 * 1024
        let metrics = DiskMetrics(totalBytes: total, freeBytes: free)
        XCTAssertEqual(metrics.usedBytes, 300 * 1024 * 1024 * 1024)
    }

    func testDiskMetricsUsedPercentage() {
        let total: UInt64 = 1_000_000_000
        let free: UInt64 = 250_000_000
        let metrics = DiskMetrics(totalBytes: total, freeBytes: free)
        XCTAssertEqual(metrics.usedPercentage, 75.0, accuracy: 0.01)
    }

    func testDiskMetricsMegaBytesPerSecond() {
        let bytesPerSec = 52_428_800.0 // 50 MB/s
        let metrics = DiskMetrics(
            readBytesPerSecond: bytesPerSec,
            writeBytesPerSecond: bytesPerSec * 2
        )
        XCTAssertEqual(metrics.readMegaBytesPerSecond, 50.0, accuracy: 0.01)
        XCTAssertEqual(metrics.writeMegaBytesPerSecond, 100.0, accuracy: 0.01)
    }

    func testDiskAndPowerServiceLivePoll() async {
        let service = DiskAndPowerService()
        let (disk, power) = await service.pollDiskAndPower()
        XCTAssertFalse(disk.volumeName.isEmpty)
        XCTAssertGreaterThan(disk.totalBytes, 0)
        XCTAssertGreaterThanOrEqual(disk.usedPercentage, 0.0)
        XCTAssertLessThanOrEqual(disk.usedPercentage, 100.0)
        XCTAssertNotNil(power.thermalState)
    }

    func testFormattersFormatBytesForDisk() {
        XCTAssertEqual(Formatters.formatBytes(512), "512 B")
        XCTAssertEqual(Formatters.formatBytes(2048), "2 KB")
        XCTAssertEqual(Formatters.formatBytes(10 * 1024 * 1024), "10 MB")
        XCTAssertEqual(Formatters.formatBytes(50 * 1024 * 1024 * 1024), "50.0 GB")
        XCTAssertEqual(Formatters.formatBytes(2 * 1024 * 1024 * 1024 * 1024), "2.0 TB")
    }
}
