import XCTest
@testable import SystemResourceViewer

final class ProcessDiskIOTests: XCTestCase {
    func testFetchProcessDiskIOCurrentProcess() {
        let pid = getpid()
        let diskIO = DarwinMachBridge.fetchProcessDiskIO(for: pid)
        XCTAssertNotNil(diskIO, "fetchProcessDiskIO should return non-nil for current process")
        if let io = diskIO {
            XCTAssertGreaterThanOrEqual(io.bytesRead, 0)
            XCTAssertGreaterThanOrEqual(io.bytesWritten, 0)
        }
    }

    func testProcessItemDiskFormatting() {
        let item = ProcessItem(
            id: 42,
            ppid: 1,
            name: "DiskTester",
            cpuPercentage: 10.0,
            memoryBytes: 50 * 1024 * 1024,
            isSuspended: false,
            diskReadBytesPerSecond: 1024 * 1024 * 5,  // 5 MB/s
            diskWriteBytesPerSecond: 1024 * 1024 * 2, // 2 MB/s
            totalDiskReadBytes: 1024 * 1024 * 500,
            totalDiskWriteBytes: 1024 * 1024 * 200
        )

        XCTAssertEqual(item.diskReadBytesPerSecond, 1024 * 1024 * 5)
        XCTAssertEqual(item.diskWriteBytesPerSecond, 1024 * 1024 * 2)
        XCTAssertEqual(item.diskBytesPerSecond, 1024 * 1024 * 7)
        XCTAssertEqual(item.totalDiskBytesPerSecond, 1024 * 1024 * 7)
        XCTAssertEqual(item.formattedDiskIO, Formatters.formatSpeed(1024 * 1024 * 7))
        XCTAssertEqual(item.formattedTotalDiskIO, Formatters.formatSpeed(1024 * 1024 * 7))
    }

    func testProcessSortingByDiskIO() {
        let lowIO = ProcessItem(
            id: 1,
            name: "Low",
            cpuPercentage: 5.0,
            memoryBytes: 100,
            diskReadBytesPerSecond: 100,
            diskWriteBytesPerSecond: 100
        )
        let highIO = ProcessItem(
            id: 2,
            name: "High",
            cpuPercentage: 2.0,
            memoryBytes: 200,
            diskReadBytesPerSecond: 10_000_000,
            diskWriteBytesPerSecond: 5_000_000
        )

        let list = [lowIO, highIO]
        let sortedDesc = list.sorted { ($0.diskReadBytesPerSecond + $0.diskWriteBytesPerSecond) > ($1.diskReadBytesPerSecond + $1.diskWriteBytesPerSecond) }
        XCTAssertEqual(sortedDesc.first?.id, 2)
        XCTAssertEqual(sortedDesc.last?.id, 1)
    }

    func testSuspendedProcessItemEquality() {
        let p1 = ProcessItem(id: 10, name: "P1", cpuPercentage: 1.0, memoryBytes: 100, isSuspended: false)
        let p2 = ProcessItem(id: 10, name: "P1", cpuPercentage: 1.0, memoryBytes: 100, isSuspended: true)
        XCTAssertNotEqual(p1, p2, "ProcessItems with different isSuspended state must not be equal")
    }
}
