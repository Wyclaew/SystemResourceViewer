import XCTest
@testable import SystemResourceViewer

@MainActor
final class ViewModelHistoryBufferTests: XCTestCase {

    func testRollingBufferMaintainsFixedCapacitySixty() {
        let vm = DashboardViewModel(interval: 5.0)

        // Initial capacity is 60 items
        XCTAssertEqual(vm.cpuHistory.count, 60)
        XCTAssertEqual(vm.memoryHistory.count, 60)
        XCTAssertEqual(vm.downloadSpeedHistory.count, 60)
        XCTAssertEqual(vm.uploadSpeedHistory.count, 60)
        XCTAssertEqual(vm.diskReadHistory.count, 60)
        XCTAssertEqual(vm.diskWriteHistory.count, 60)
    }

    func testMenuBarTitleDynamicFormatting() {
        let vm = DashboardViewModel(interval: 5.0)

        // Initial title format
        XCTAssertTrue(vm.menuBarTitle.contains("CPU"))
        XCTAssertTrue(vm.menuBarTitle.contains("RAM"))
        XCTAssertTrue(vm.menuBarTitle.contains("↓"))
    }

    func testWindowAndPopoverStateModeToggle() {
        let vm = DashboardViewModel(interval: 5.0)

        XCTAssertFalse(vm.isPopoverOpen)
        XCTAssertFalse(vm.isDashboardWindowOpen)

        vm.isPopoverOpen = true
        XCTAssertTrue(vm.isPopoverOpen)

        vm.isDashboardWindowOpen = true
        XCTAssertTrue(vm.isDashboardWindowOpen)

        vm.isPopoverOpen = false
        XCTAssertFalse(vm.isPopoverOpen)
        XCTAssertTrue(vm.isDashboardWindowOpen)

        vm.isDashboardWindowOpen = false
        XCTAssertFalse(vm.isDashboardWindowOpen)
    }
}
