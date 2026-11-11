import XCTest
@testable import SystemResourceViewer

final class ProcessBoundaryTests: XCTestCase {

    func testEmptyProcessTableFiltering() {
        let empty: [ProcessItem] = []
        let filteredAll = ProcessFilterHelper.filter(processes: empty, category: .all)
        let filteredApps = ProcessFilterHelper.filter(processes: empty, category: .apps)
        let filteredSearch = ProcessFilterHelper.filter(processes: empty, category: .all, searchQuery: "Safari")

        XCTAssertTrue(filteredAll.isEmpty)
        XCTAssertTrue(filteredApps.isEmpty)
        XCTAssertTrue(filteredSearch.isEmpty)
    }

    func testCaseInsensitiveSearchQuery() {
        let item = ProcessItem(id: 1234, ppid: 1, name: "WindowServer", cpuPercentage: 4.5, memoryBytes: 200 * 1024 * 1024)
        let matchedLower = ProcessFilterHelper.filter(processes: [item], category: .all, searchQuery: "windowserver")
        let matchedUpper = ProcessFilterHelper.filter(processes: [item], category: .all, searchQuery: "WINDOW")
        let matchedExact = ProcessFilterHelper.filter(processes: [item], category: .all, searchQuery: "WindowServer")

        XCTAssertEqual(matchedLower.count, 1)
        XCTAssertEqual(matchedUpper.count, 1)
        XCTAssertEqual(matchedExact.count, 1)
    }

    func testPIDSearchQuery() {
        let item1 = ProcessItem(id: 8492, ppid: 1, name: "Code", cpuPercentage: 1.0, memoryBytes: 100 * 1024 * 1024)
        let item2 = ProcessItem(id: 9912, ppid: 1, name: "Xcode", cpuPercentage: 2.0, memoryBytes: 200 * 1024 * 1024)

        let matched = ProcessFilterHelper.filter(processes: [item1, item2], category: .all, searchQuery: "8492")
        XCTAssertEqual(matched.count, 1)
        XCTAssertEqual(matched.first?.id, 8492)
    }

    func testSyntheticKernelProcessIDNegativeOne() {
        let kernel = ProcessItem(id: -1, ppid: 0, name: "macOS System & Kernel", cpuPercentage: 12.0, memoryBytes: 0)
        let systemFiltered = ProcessFilterHelper.filter(processes: [kernel], category: .system)
        XCTAssertEqual(systemFiltered.count, 1)

        let actionResult = ProcessFilterHelper.performAction(pid: kernel.id, force: true)
        XCTAssertEqual(actionResult, .failure("Cannot terminate system initialization process."))
    }

    func testNonMatchingSearchReturnsEmpty() {
        let item = ProcessItem(id: 500, ppid: 1, name: "Finder", cpuPercentage: 0.5, memoryBytes: 50 * 1024 * 1024)
        let result = ProcessFilterHelper.filter(processes: [item], category: .all, searchQuery: "NonExistentProcessName12345")
        XCTAssertTrue(result.isEmpty)
    }

    func testProcessActionSelfPIDProtection() {
        let currentPID = getpid()
        let termRes = ProcessAction.terminate(pid: currentPID)
        XCTAssertEqual(termRes, .failure("Cannot terminate the active Resource Monitor application directly."))

        let forceRes = ProcessAction.forceKill(pid: currentPID)
        XCTAssertEqual(forceRes, .failure("Cannot terminate the active Resource Monitor application directly."))
    }
}
