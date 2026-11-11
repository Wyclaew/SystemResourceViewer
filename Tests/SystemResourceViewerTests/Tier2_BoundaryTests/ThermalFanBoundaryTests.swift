import XCTest
@testable import SystemResourceViewer

final class ThermalFanBoundaryTests: XCTestCase {

    func testFanlessHardwareDetectionZeroFans() {
        let metrics = ThermalMetricsContract(fanSpeeds: [])
        XCTAssertTrue(metrics.isFanless)
        XCTAssertEqual(metrics.fanSpeeds.count, 0)
    }

    func testDualFanIndependentRPMTracking() {
        let leftFan = FanTelemetry(id: 0, name: "Left Fan", currentRPM: 2100, minRPM: 1200, maxRPM: 5500)
        let rightFan = FanTelemetry(id: 1, name: "Right Fan", currentRPM: 3800, minRPM: 1200, maxRPM: 5500)

        let metrics = ThermalMetricsContract(fanSpeeds: [leftFan, rightFan])
        XCTAssertFalse(metrics.isFanless)
        XCTAssertEqual(metrics.fanSpeeds.count, 2)
        XCTAssertEqual(metrics.fanSpeeds[0].currentRPM, 2100)
        XCTAssertEqual(metrics.fanSpeeds[1].currentRPM, 3800)
    }

    func testFanStoppedZeroRPMState() {
        let stopped = FanTelemetry(id: 0, name: "Fan", currentRPM: 0, minRPM: 0, maxRPM: 5000)
        XCTAssertEqual(stopped.percentage, 0.0)
    }

    func testFanMaxRPMLimitBound() {
        let maxed = FanTelemetry(id: 0, name: "Fan", currentRPM: 6000, minRPM: 1000, maxRPM: 6000)
        XCTAssertEqual(maxed.percentage, 100.0)
    }

    func testInvertedOrZeroRangeRPMGuard() {
        let invalid = FanTelemetry(id: 0, name: "Broken Fan", currentRPM: 2000, minRPM: 4000, maxRPM: 2000)
        // Guard against maxRPM <= minRPM division by zero
        XCTAssertEqual(invalid.percentage, 0.0)
    }
}
