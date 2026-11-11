import XCTest
@testable import SystemResourceViewer

final class ThermalFanMetricsTests: XCTestCase {

    func testThermalMetricsDefaultEmpty() {
        let metrics = ThermalMetricsContract.empty
        XCTAssertNil(metrics.socDieTemperature)
        XCTAssertNil(metrics.peakDieTemperature)
        XCTAssertNil(metrics.batteryTemperature)
        XCTAssertNil(metrics.storageTemperature)
        XCTAssertEqual(metrics.thermalState, .nominal)
        XCTAssertTrue(metrics.fanSpeeds.isEmpty)
        XCTAssertTrue(metrics.isFanless)
    }

    func testFanTelemetryInitializationAndPercentage() {
        let fan = FanTelemetry(
            id: 0,
            name: "Main Fan",
            currentRPM: 3000,
            minRPM: 1000,
            maxRPM: 5000
        )
        XCTAssertEqual(fan.id, 0)
        XCTAssertEqual(fan.name, "Main Fan")
        XCTAssertEqual(fan.currentRPM, 3000)
        // (3000 - 1000) / (5000 - 1000) = 2000 / 4000 = 50.0%
        XCTAssertEqual(fan.percentage, 50.0, accuracy: 0.01)
    }

    func testThermalMetricsIsFanless() {
        let fanless = ThermalMetricsContract(fanSpeeds: [])
        XCTAssertTrue(fanless.isFanless)

        let withFan = ThermalMetricsContract(fanSpeeds: [
            FanTelemetry(id: 0, name: "Fan 1", currentRPM: 2200)
        ])
        XCTAssertFalse(withFan.isFanless)
    }

    func testMultiChannelTemperatures() {
        let metrics = ThermalMetricsContract(
            socDieTemperature: 42.5,
            peakDieTemperature: 48.0,
            batteryTemperature: 31.0,
            storageTemperature: 36.5,
            thermalState: .nominal
        )
        XCTAssertEqual(metrics.socDieTemperature, 42.5)
        XCTAssertEqual(metrics.peakDieTemperature, 48.0)
        XCTAssertEqual(metrics.batteryTemperature, 31.0)
        XCTAssertEqual(metrics.storageTemperature, 36.5)
        XCTAssertEqual(metrics.thermalState, .nominal)
    }

    func testPowerMetricsThermalStateMapping() {
        let nominal = PowerMetrics(thermalState: .nominal)
        XCTAssertEqual(nominal.thermalStateDescription, "Nominal")
        XCTAssertEqual(nominal.thermalStateSymbol, "flame")

        let fair = PowerMetrics(thermalState: .fair)
        XCTAssertEqual(fair.thermalStateDescription, "Fair")
        XCTAssertEqual(fair.thermalStateSymbol, "flame.fill")

        let serious = PowerMetrics(thermalState: .serious)
        XCTAssertEqual(serious.thermalStateDescription, "Serious")
        XCTAssertEqual(serious.thermalStateSymbol, "exclamationmark.shield.fill")

        let critical = PowerMetrics(thermalState: .critical)
        XCTAssertEqual(critical.thermalStateDescription, "Critical")
        XCTAssertEqual(critical.thermalStateSymbol, "shield.slash.fill")
    }
}
