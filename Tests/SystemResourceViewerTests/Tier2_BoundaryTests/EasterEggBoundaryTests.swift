import XCTest
@testable import SystemResourceViewer

final class EasterEggBoundaryTests: XCTestCase {

    func testBoundaryAtSixClicks() {
        let sm = EasterEggStateMachine()
        for _ in 1...6 {
            sm.registerClick()
        }
        XCTAssertEqual(sm.state.clickCount, 6)
        XCTAssertFalse(sm.state.isUnlocked)
        XCTAssertFalse(sm.state.showConfetti)
    }

    func testBoundaryAtSevenClicks() {
        let sm = EasterEggStateMachine()
        for _ in 1...7 {
            sm.registerClick()
        }
        XCTAssertEqual(sm.state.clickCount, 7)
        XCTAssertTrue(sm.state.isUnlocked)
        XCTAssertTrue(sm.state.showConfetti)
    }

    func testBoundaryAtEightPlusClicks() {
        let sm = EasterEggStateMachine()
        for _ in 1...8 {
            sm.registerClick()
        }
        XCTAssertEqual(sm.state.clickCount, 8)
        XCTAssertTrue(sm.state.isUnlocked)
        XCTAssertFalse(sm.state.showConfetti)
    }

    func testRapidConsecutiveClicksFiftyTimes() {
        let sm = EasterEggStateMachine()
        for _ in 1...50 {
            sm.registerClick()
        }
        XCTAssertEqual(sm.state.clickCount, 50)
        XCTAssertTrue(sm.state.isUnlocked)
        XCTAssertFalse(sm.state.showConfetti)
        XCTAssertTrue(sm.hasFiredConfettiOnce)
    }

    func testPreUnlockedStateRestoration() {
        // Simulating @AppStorage loaded state where previously unlocked
        let savedState = AuthorEasterEggState(clickCount: 7, isUnlocked: true, showConfetti: false)
        let sm = EasterEggStateMachine(initialState: savedState, hasFiredConfettiOnce: true)

        XCTAssertTrue(sm.state.isUnlocked)
        XCTAssertFalse(sm.state.showConfetti)

        // Registering another click after restoration must not re-fire confetti
        sm.registerClick()
        XCTAssertTrue(sm.state.isUnlocked)
        XCTAssertFalse(sm.state.showConfetti)
    }
}
