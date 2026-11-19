import XCTest
@testable import SystemResourceViewer

final class MultiTimelineHistoryTests: XCTestCase {
    func testTimelineRangeSampleCounts() {
        XCTAssertEqual(HistoryTimelineRange.oneMinute.sampleCount, 60)
        XCTAssertEqual(HistoryTimelineRange.oneMinute.label, "1 Minute")

        XCTAssertEqual(HistoryTimelineRange.fiveMinutes.sampleCount, 300)
        XCTAssertEqual(HistoryTimelineRange.fiveMinutes.label, "5 Minutes")

        XCTAssertEqual(HistoryTimelineRange.fifteenMinutes.sampleCount, 900)
        XCTAssertEqual(HistoryTimelineRange.fifteenMinutes.label, "15 Minutes")
    }

    func testTimelineStatisticsCalculation() {
        let values: [Double] = [10.0, 20.0, 30.0, 40.0, 50.0]
        let stats = TimelineStatistics(values: values)

        XCTAssertEqual(stats.min, 10.0, accuracy: 0.001)
        XCTAssertEqual(stats.max, 50.0, accuracy: 0.001)
        XCTAssertEqual(stats.mean, 30.0, accuracy: 0.001)
        XCTAssertEqual(stats.current, 50.0, accuracy: 0.001)
    }

    func testTimelineStatisticsEmptyArray() {
        let stats = TimelineStatistics(values: [])
        XCTAssertEqual(stats.min, 0.0)
        XCTAssertEqual(stats.max, 0.0)
        XCTAssertEqual(stats.mean, 0.0)
        XCTAssertEqual(stats.current, 0.0)
    }

    func testTimelineStatisticsSingleElement() {
        let stats = TimelineStatistics(values: [42.5])
        XCTAssertEqual(stats.min, 42.5)
        XCTAssertEqual(stats.max, 42.5)
        XCTAssertEqual(stats.mean, 42.5)
        XCTAssertEqual(stats.current, 42.5)
    }

    @MainActor
    func testDashboardViewModelExtendedHistoryBuffers() {
        let vm = DashboardViewModel()

        // Verify initial state
        XCTAssertEqual(vm.cpuHistory.count, 60, "Backward-compatible cpuHistory should have 60 initial points")
        XCTAssertEqual(vm.cpuHistory15m.count, 900, "cpuHistory15m should have 900 initial points")
        XCTAssertEqual(vm.memoryHistory15m.count, 900)
        XCTAssertEqual(vm.gpuHistory15m.count, 900)
        XCTAssertEqual(vm.socTemperatureHistory15m.count, 900)
        XCTAssertEqual(vm.downloadSpeedHistory15m.count, 900)
        XCTAssertEqual(vm.uploadSpeedHistory15m.count, 900)
        XCTAssertEqual(vm.diskReadHistory15m.count, 900)
        XCTAssertEqual(vm.diskWriteHistory15m.count, 900)

        // Test historySlice
        let slice1m = vm.historySlice(for: vm.cpuHistory15m, range: .oneMinute)
        XCTAssertEqual(slice1m.count, 60)

        let slice5m = vm.historySlice(for: vm.cpuHistory15m, range: .fiveMinutes)
        XCTAssertEqual(slice5m.count, 300)

        let slice15m = vm.historySlice(for: vm.cpuHistory15m, range: .fifteenMinutes)
        XCTAssertEqual(slice15m.count, 900)
    }
}
