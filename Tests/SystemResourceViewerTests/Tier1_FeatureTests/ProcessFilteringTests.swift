import XCTest
@testable import SystemResourceViewer

final class ProcessFilteringTests: XCTestCase {

    func testProcessCategoriesCountAndValues() {
        XCTAssertEqual(ProcessCategory.allCases.count, 5)
        XCTAssertEqual(ProcessCategory.all.rawValue, "All")
        XCTAssertEqual(ProcessCategory.apps.rawValue, "Apps")
        XCTAssertEqual(ProcessCategory.daemons.rawValue, "Daemons")
        XCTAssertEqual(ProcessCategory.system.rawValue, "System")
        XCTAssertEqual(ProcessCategory.highLoad.rawValue, "High Load")
    }

    func testProcessFilteringCategoryApps() {
        let app = ProcessItem(id: 101, ppid: 1, name: "Safari", bundleIdentifier: "com.apple.Safari", cpuPercentage: 2.0, memoryBytes: 150 * 1024 * 1024)
        let daemon = ProcessItem(id: 202, ppid: 1, name: "cron", bundleIdentifier: nil, cpuPercentage: 0.1, memoryBytes: 10 * 1024 * 1024)
        let system = ProcessItem(id: 1, ppid: 0, name: "launchd", bundleIdentifier: nil, cpuPercentage: 0.5, memoryBytes: 20 * 1024 * 1024)

        let filtered = ProcessFilterHelper.filter(processes: [app, daemon, system], category: .apps)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.name, "Safari")
    }

    func testProcessFilteringCategorySystem() {
        let app = ProcessItem(id: 101, ppid: 1, name: "Notes", bundleIdentifier: "com.apple.Notes", cpuPercentage: 1.0, memoryBytes: 50 * 1024 * 1024)
        let kernel = ProcessItem(id: 0, ppid: 0, name: "kernel_task", bundleIdentifier: nil, cpuPercentage: 3.0, memoryBytes: 800 * 1024 * 1024)
        let launchd = ProcessItem(id: 1, ppid: 0, name: "launchd", bundleIdentifier: nil, cpuPercentage: 0.2, memoryBytes: 30 * 1024 * 1024)

        let filtered = ProcessFilterHelper.filter(processes: [app, kernel, launchd], category: .system)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.contains { $0.name == "kernel_task" })
        XCTAssertTrue(filtered.contains { $0.name == "launchd" })
    }

    func testProcessFilteringCategoryHighLoad() {
        let normal = ProcessItem(id: 101, ppid: 1, name: "TextEdit", cpuPercentage: 1.0, memoryBytes: 50 * 1024 * 1024)
        let highCPU = ProcessItem(id: 102, ppid: 1, name: "Compiler", cpuPercentage: 85.0, memoryBytes: 200 * 1024 * 1024)
        let highMem = ProcessItem(id: 103, ppid: 1, name: "Database", cpuPercentage: 2.0, memoryBytes: 1024 * 1024 * 1024) // 1 GB

        let filtered = ProcessFilterHelper.filter(processes: [normal, highCPU, highMem], category: .highLoad)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.contains { $0.name == "Compiler" })
        XCTAssertTrue(filtered.contains { $0.name == "Database" })
    }

    func testProcessTotalCPUAndMemoryTreeAggregation() {
        let child1 = ProcessItem(id: 201, ppid: 200, name: "Renderer 1", cpuPercentage: 15.0, memoryBytes: 200 * 1024 * 1024)
        let child2 = ProcessItem(id: 202, ppid: 200, name: "Renderer 2", cpuPercentage: 20.0, memoryBytes: 300 * 1024 * 1024)
        let parent = ProcessItem(id: 200, ppid: 1, name: "Browser Main", cpuPercentage: 5.0, memoryBytes: 100 * 1024 * 1024, children: [child1, child2])

        // Total CPU = 5 + 15 + 20 = 40.0%
        XCTAssertEqual(parent.totalCPU, 40.0, accuracy: 0.01)
        // Total Memory = 100 + 200 + 300 = 600 MB
        XCTAssertEqual(parent.totalMemory, 600 * 1024 * 1024)
        XCTAssertTrue(parent.hasChildren)
    }

    func testProcessActionSafelyRejectsInvalidPIDs() {
        let resultPID0 = ProcessFilterHelper.performAction(pid: 0, force: false)
        XCTAssertEqual(resultPID0, .failure("Cannot terminate system initialization process."))

        let resultPID1 = ProcessFilterHelper.performAction(pid: 1, force: true)
        XCTAssertEqual(resultPID1, .failure("Cannot terminate system initialization process."))
    }
}
