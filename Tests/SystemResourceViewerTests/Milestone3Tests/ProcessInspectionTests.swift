import XCTest
@testable import SystemResourceViewer

final class ProcessInspectionTests: XCTestCase {
    func testFetchProcessDetailCurrentProcess() {
        let pid = getpid()
        let processItem = ProcessItem(
            id: pid,
            name: "xctest",
            cpuPercentage: 1.0,
            memoryBytes: 50 * 1024 * 1024
        )
        let item = DarwinMachBridge.fetchProcessDetail(for: processItem)

        XCTAssertEqual(item.id, pid)
        XCTAssertGreaterThan(item.threadCount, 0, "Current process must have at least 1 thread")
        XCTAssertGreaterThan(item.residentBytes, 0, "Current process must have resident memory")
        XCTAssertNotNil(item.startTime, "Current process must have a valid start time")
        XCTAssertLessThanOrEqual(item.startTime ?? Date.distantFuture, Date(), "Start time must be in the past")
    }

    func testFetchProcessOpenFileDescriptorsCount() {
        let pid = getpid()
        let count = DarwinMachBridge.fetchProcessOpenFileDescriptorsCount(for: pid)
        XCTAssertNotNil(count, "Open file descriptors count should be retrievable for current process")
        XCTAssertGreaterThan(count ?? 0, 0, "Current process should have at least standard file descriptors (0, 1, 2) open")
    }

    func testProcessDetailItemFormatters() {
        let item = ProcessDetailItem(
            id: 1234,
            ppid: 1,
            name: "TestRunner",
            executablePath: "/usr/bin/test",
            ownerUser: "tester",
            architecture: "arm64",
            isRosetta: false,
            isProtected: false,
            isSuspended: false,
            category: .apps,
            cpuPercentage: 5.5,
            threadCount: 8,
            residentBytes: 150 * 1024 * 1024,     // 150 MB
            virtualBytes: 2 * 1024 * 1024 * 1024, // 2 GB
            openFileDescriptorsCount: 24,
            startTime: Date().addingTimeInterval(-3600), // 1 hour ago
            contextSwitches: 1500,
            faults: 320,
            pageins: 12,
            cowFaults: 85,
            diskReadBytesPerSecond: 1024 * 100,
            diskWriteBytesPerSecond: 1024 * 50,
            totalDiskReadBytes: 1024 * 1024,
            totalDiskWriteBytes: 512 * 1024
        )

        XCTAssertEqual(item.formattedVirtualMemory, Formatters.formatBytes(2 * 1024 * 1024 * 1024))
        XCTAssertEqual(item.formattedResidentMemory, Formatters.formatBytes(150 * 1024 * 1024))
        XCTAssertEqual(item.formattedDiskReadSpeed, Formatters.formatSpeed(1024 * 100))
        XCTAssertEqual(item.formattedDiskWriteSpeed, Formatters.formatSpeed(1024 * 50))
        XCTAssertEqual(item.formattedTotalDiskRead, Formatters.formatBytes(1024 * 1024))
        XCTAssertEqual(item.formattedTotalDiskWrite, Formatters.formatBytes(512 * 1024))

        let summary = item.formattedDiagnosticsSummary
        XCTAssertTrue(summary.contains("TestRunner (PID: 1234)"), "Summary must contain name and PID")
        XCTAssertTrue(summary.contains("Threads: 8"), "Summary must contain thread count")
        XCTAssertTrue(summary.contains("Open File Descriptors: 24"), "Summary must contain open file descriptors")
        XCTAssertTrue(summary.contains("Context Switches: 1500"), "Summary must contain context switches")
    }
}
