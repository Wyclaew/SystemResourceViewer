import XCTest
@testable import SystemResourceViewer

final class MinimalModePerformanceTests: XCTestCase {

    func testMinimalModeExecutionTiming() async {
        let scheduler = MetricsScheduler(interval: 0.05)
        await scheduler.setPollingMode(.minimal)

        let stream = await scheduler.metricsStream()
        var iterator = stream.makeAsyncIterator()

        let start = DispatchTime.now()
        let snapshot = await iterator.next()
        let end = DispatchTime.now()

        XCTAssertNotNil(snapshot)
        XCTAssertTrue(snapshot?.processes.isEmpty ?? false)

        let elapsedMs = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
        // Minimal mode should be extremely lightweight (< 50ms)
        XCTAssertLessThan(elapsedMs, 50.0, "Minimal mode tick took too long: \(elapsedMs) ms")

        await scheduler.stop()
    }

    func testMinimalModeTelemetryFidelity() async {
        let scheduler = MetricsScheduler(interval: 0.05)
        await scheduler.setPollingMode(.minimal)

        let stream = await scheduler.metricsStream()
        var iterator = stream.makeAsyncIterator()

        let snapshot = await iterator.next()
        guard let s = snapshot else {
            XCTFail("Failed to receive snapshot")
            return
        }

        // Lightweight stats are still accurately populated
        XCTAssertGreaterThan(s.memory.totalBytes, 0)
        XCTAssertGreaterThan(s.disk.totalBytes, 0)
        XCTAssertFalse(s.network.primaryInterfaceName.isEmpty)
        XCTAssertTrue(s.processes.isEmpty)

        await scheduler.stop()
    }
}
