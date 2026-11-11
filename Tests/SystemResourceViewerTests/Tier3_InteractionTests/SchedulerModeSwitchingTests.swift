import XCTest
@testable import SystemResourceViewer

final class SchedulerModeSwitchingTests: XCTestCase {

    func testSchedulerModeSwitchingMinimalToFull() async {
        let scheduler = MetricsScheduler(interval: 0.1)
        let stream = await scheduler.metricsStream()

        var iterator = stream.makeAsyncIterator()

        // 1. In default full mode, processes should be populated
        let snapshot1 = await iterator.next()
        XCTAssertNotNil(snapshot1)

        // 2. Switch to minimal mode
        await scheduler.setPollingMode(.minimal)
        let snapshot2 = await iterator.next()
        XCTAssertNotNil(snapshot2)
        // In minimal mode, process table polling is bypassed
        XCTAssertTrue(snapshot2?.processes.isEmpty ?? false)

        // 3. Switch back to full mode
        await scheduler.setPollingMode(.full)
        let snapshot3 = await iterator.next()
        XCTAssertNotNil(snapshot3)

        await scheduler.stop()
    }

    func testSchedulerRefreshIntervalDynamicUpdate() async {
        let scheduler = MetricsScheduler(interval: 0.2)
        await scheduler.setRefreshInterval(0.1)

        let stream = await scheduler.metricsStream()
        var iterator = stream.makeAsyncIterator()

        let snapshot = await iterator.next()
        XCTAssertNotNil(snapshot)

        // Change interval again while streaming
        await scheduler.setRefreshInterval(0.05)
        let snapshot2 = await iterator.next()
        XCTAssertNotNil(snapshot2)

        await scheduler.stop()
    }

    func testSchedulerMultipleStopCallsSafety() async {
        let scheduler = MetricsScheduler(interval: 0.1)
        await scheduler.startPolling()
        await scheduler.stop()
        await scheduler.stop() // Idempotent stop
    }
}
