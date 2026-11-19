import XCTest
@testable import SystemResourceViewer

final class EasterEggPreservationTests: XCTestCase {
    @MainActor
    func testEasterEggPersistenceAcrossTabNavigation() {
        let vm = DashboardViewModel()

        // Initial state: not unlocked, 0 clicks
        XCTAssertFalse(vm.easterEggStateMachine.state.isUnlocked)
        XCTAssertEqual(vm.easterEggStateMachine.state.clickCount, 0)
        XCTAssertEqual(vm.selectedTab, .processes)

        // Switch tabs and register clicks
        vm.selectedTab = .diagnostics
        vm.easterEggStateMachine.registerClick()
        vm.easterEggStateMachine.registerClick()
        XCTAssertEqual(vm.easterEggStateMachine.state.clickCount, 2)

        vm.selectedTab = .history
        vm.easterEggStateMachine.registerClick()
        vm.easterEggStateMachine.registerClick()
        XCTAssertEqual(vm.easterEggStateMachine.state.clickCount, 4)

        vm.selectedTab = .systemProfile
        vm.easterEggStateMachine.registerClick()
        vm.easterEggStateMachine.registerClick()
        XCTAssertEqual(vm.easterEggStateMachine.state.clickCount, 6)

        // 7th click should unlock
        vm.selectedTab = .processes
        vm.easterEggStateMachine.registerClick()
        XCTAssertEqual(vm.easterEggStateMachine.state.clickCount, 7)
        XCTAssertTrue(vm.easterEggStateMachine.state.isUnlocked, "7 clicks must unlock the Easter egg")

        // Switch to other tabs, state remains unlocked
        vm.selectedTab = .history
        XCTAssertTrue(vm.easterEggStateMachine.state.isUnlocked, "Easter egg unlock must persist across tabs")

        vm.selectedTab = .diagnostics
        XCTAssertTrue(vm.easterEggStateMachine.state.isUnlocked, "Easter egg unlock must persist across tabs")
    }
}
