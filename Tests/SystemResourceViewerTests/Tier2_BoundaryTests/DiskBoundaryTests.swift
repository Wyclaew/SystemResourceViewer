import XCTest
@testable import SystemResourceViewer

final class DiskBoundaryTests: XCTestCase {

    func testZeroTotalBytesDivByZeroProtection() {
        let metrics = DiskMetrics(totalBytes: 0, freeBytes: 0)
        XCTAssertEqual(metrics.usedPercentage, 0.0)
        XCTAssertEqual(metrics.usedBytes, 0)
    }

    func testOneHundredPercentFullVolume() {
        let total: UInt64 = 1_000_000_000
        let metrics = DiskMetrics(totalBytes: total, freeBytes: 0)
        XCTAssertEqual(metrics.usedBytes, total)
        XCTAssertEqual(metrics.usedPercentage, 100.0, accuracy: 0.01)
    }

    func testFreeBytesExceedingTotalBytesAnomaly() {
        // Corrupted file system reported free > total
        let total: UInt64 = 500_000_000
        let free: UInt64 = 600_000_000
        let metrics = DiskMetrics(totalBytes: total, freeBytes: free)
        XCTAssertEqual(metrics.usedBytes, 0)
        XCTAssertEqual(metrics.usedPercentage, 0.0)
    }

    func testZeroThroughputFormatting() {
        let metrics = DiskMetrics(readBytesPerSecond: 0.0, writeBytesPerSecond: 0.0)
        XCTAssertEqual(metrics.readMegaBytesPerSecond, 0.0)
        XCTAssertEqual(metrics.writeMegaBytesPerSecond, 0.0)
    }

    func testExtremeThroughputFormatting() {
        let extremeRead = 10.0 * 1024.0 * 1024.0 * 1024.0 // 10 GB/s
        let metrics = DiskMetrics(readBytesPerSecond: extremeRead, writeBytesPerSecond: extremeRead)
        XCTAssertEqual(metrics.readMegaBytesPerSecond, 10240.0, accuracy: 0.1)
        XCTAssertEqual(Formatters.formatSpeed(extremeRead), "10.0 GB/s")
    }
}
