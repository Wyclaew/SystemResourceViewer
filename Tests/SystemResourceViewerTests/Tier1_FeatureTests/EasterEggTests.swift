import XCTest
@testable import SystemResourceViewer

final class EasterEggTests: XCTestCase {

    func testEasterEggInitialState() {
        let sm = EasterEggStateMachine()
        XCTAssertEqual(sm.state.clickCount, 0)
        XCTAssertFalse(sm.state.isUnlocked)
        XCTAssertFalse(sm.state.showConfetti)
        XCTAssertFalse(sm.hasFiredConfettiOnce)
    }

    func testEasterEggClicksOneThroughSix() {
        let sm = EasterEggStateMachine()
        for i in 1...6 {
            sm.registerClick()
            XCTAssertEqual(sm.state.clickCount, i)
            XCTAssertFalse(sm.state.isUnlocked, "Should not unlock at click \(i)")
            XCTAssertFalse(sm.state.showConfetti, "Should not show confetti at click \(i)")
        }
    }

    func testEasterEggExactlySeventhClick() {
        let sm = EasterEggStateMachine()
        for _ in 1...6 {
            sm.registerClick()
        }
        sm.registerClick() // 7th click

        XCTAssertEqual(sm.state.clickCount, 7)
        XCTAssertTrue(sm.state.isUnlocked, "Must unlock at 7th click")
        XCTAssertTrue(sm.state.showConfetti, "Must trigger confetti on 7th click")
        XCTAssertTrue(sm.hasFiredConfettiOnce)
    }

    func testEasterEggEighthClickDoesNotRefireConfetti() {
        let sm = EasterEggStateMachine()
        for _ in 1...7 {
            sm.registerClick()
        }
        XCTAssertTrue(sm.state.showConfetti)

        sm.registerClick() // 8th click
        XCTAssertEqual(sm.state.clickCount, 8)
        XCTAssertTrue(sm.state.isUnlocked, "Must remain unlocked")
        XCTAssertFalse(sm.state.showConfetti, "Confetti must NOT fire again after 7th click")
    }

    func testEasterEggDismissConfetti() {
        let sm = EasterEggStateMachine()
        for _ in 1...7 {
            sm.registerClick()
        }
        XCTAssertTrue(sm.state.showConfetti)

        sm.dismissConfetti()
        XCTAssertFalse(sm.state.showConfetti)
        XCTAssertTrue(sm.state.isUnlocked)
    }

    func testEasterEggReset() {
        let sm = EasterEggStateMachine()
        for _ in 1...7 {
            sm.registerClick()
        }
        sm.reset()
        XCTAssertEqual(sm.state.clickCount, 0)
        XCTAssertFalse(sm.state.isUnlocked)
        XCTAssertFalse(sm.state.showConfetti)
        XCTAssertFalse(sm.hasFiredConfettiOnce)
    }

    func testAuthorEasterEggStateEquatableAndInitial() {
        let s1 = AuthorEasterEggState.initial
        let s2 = AuthorEasterEggState(clickCount: 0, isUnlocked: false, showConfetti: false)
        XCTAssertEqual(s1, s2)

        let s3 = AuthorEasterEggState(clickCount: 7, isUnlocked: true, showConfetti: true)
        XCTAssertNotEqual(s1, s3)
        XCTAssertEqual(s3.clickCount, 7)
        XCTAssertTrue(s3.isUnlocked)
        XCTAssertTrue(s3.showConfetti)
    }

    @MainActor
    func testConfettiViewParticleGeneration() {
        let confetti = ConfettiView(particleCount: 50, duration: 3.0)
        XCTAssertEqual(confetti.particles.count, 50)
        XCTAssertEqual(confetti.duration, 3.0)

        // Verify physical constraints of generated particles
        var circleCount = 0
        var rectCount = 0
        for p in confetti.particles {
            XCTAssertGreaterThanOrEqual(p.initialFractionX, 0.3)
            XCTAssertLessThanOrEqual(p.initialFractionX, 0.7)
            XCTAssertGreaterThanOrEqual(p.initialFractionY, 0.5)
            XCTAssertLessThanOrEqual(p.initialFractionY, 0.85)
            XCTAssertGreaterThan(p.gravity, 0)
            XCTAssertGreaterThan(p.width, 0)
            XCTAssertGreaterThan(p.height, 0)
            if p.isCircle {
                circleCount += 1
            } else {
                rectCount += 1
            }
        }
        XCTAssertGreaterThan(circleCount, 0, "Must generate circle particles")
        XCTAssertGreaterThan(rectCount, 0, "Must generate rectangle particles")
    }

    @MainActor
    func testDashboardViewModelEasterEggIntegration() {
        let vm = DashboardViewModel()
        XCTAssertEqual(vm.easterEggStateMachine.state.clickCount, 0)
        XCTAssertFalse(vm.easterEggStateMachine.state.isUnlocked)

        for _ in 1...7 {
            vm.easterEggStateMachine.registerClick()
        }
        XCTAssertTrue(vm.easterEggStateMachine.state.isUnlocked)
        XCTAssertTrue(vm.easterEggStateMachine.hasFiredConfettiOnce)
    }

    func testConcurrentClicksThreadSafety() async {
        let sm = EasterEggStateMachine()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    sm.registerClick()
                }
            }
        }
        XCTAssertEqual(sm.state.clickCount, 100)
        XCTAssertTrue(sm.state.isUnlocked)
        XCTAssertTrue(sm.hasFiredConfettiOnce)
    }
}

