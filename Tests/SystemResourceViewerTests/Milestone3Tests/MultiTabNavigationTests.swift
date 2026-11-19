import XCTest
@testable import SystemResourceViewer

final class MultiTabNavigationTests: XCTestCase {
    func testDashboardTabCasesAndTitles() {
        let allCases = DashboardTab.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertEqual(DashboardTab.processes.rawValue, "Processes")
        XCTAssertEqual(DashboardTab.diagnostics.rawValue, "Diagnostics")
        XCTAssertEqual(DashboardTab.history.rawValue, "History")
        XCTAssertEqual(DashboardTab.systemProfile.rawValue, "System Profile")
        XCTAssertEqual(DashboardTab.processes.id, "Processes")
        XCTAssertFalse(DashboardTab.processes.systemImage.isEmpty)
    }

    func testDashboardTabCodable() throws {
        for tab in DashboardTab.allCases {
            let encoded = try JSONEncoder().encode(tab)
            let decoded = try JSONDecoder().decode(DashboardTab.self, from: encoded)
            XCTAssertEqual(tab, decoded)
        }
    }

    @MainActor
    func testTabSwitchingPreservesTelemetryState() {
        let vm = DashboardViewModel()

        vm.selectedTab = .processes
        XCTAssertEqual(vm.selectedTab, .processes)

        vm.selectedTab = .diagnostics
        XCTAssertEqual(vm.selectedTab, .diagnostics)

        vm.selectedTab = .history
        XCTAssertEqual(vm.selectedTab, .history)

        vm.selectedTab = .systemProfile
        XCTAssertEqual(vm.selectedTab, .systemProfile)

        // Telemetry history buffers should remain populated
        XCTAssertEqual(vm.cpuHistory.count, 60)
        XCTAssertEqual(vm.cpuHistory15m.count, 900)
    }
}
