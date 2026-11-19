import XCTest
@testable import SystemResourceViewer

final class SystemAlertTests: XCTestCase {
    func testHighCPUEvaluation() {
        let config = AlertConfiguration(cpuThreshold: 90.0, cpuAlertsEnabled: true, cooldownInterval: 60)
        let firedMap: [AlertType: Date] = [:]

        // Normal CPU (50%)
        let cpuNormal = CPUMetrics(totalUsage: 50.0, userPercentage: 25.0, systemPercentage: 25.0, idlePercentage: 50.0)
        let metricsNormal = SystemMetrics(cpu: cpuNormal)
        let resultNormal = AlertEvaluator.evaluate(metrics: metricsNormal, config: config, lastFired: firedMap)
        XCTAssertTrue(resultNormal.newAlerts.isEmpty, "No alerts should be triggered at 50% CPU")

        // High CPU (92%)
        let cpuHigh = CPUMetrics(totalUsage: 92.0, userPercentage: 50.0, systemPercentage: 42.0, idlePercentage: 8.0)
        let metricsHigh = SystemMetrics(cpu: cpuHigh)
        let resultHigh = AlertEvaluator.evaluate(metrics: metricsHigh, config: config, lastFired: firedMap)
        XCTAssertEqual(resultHigh.newAlerts.count, 1)
        XCTAssertEqual(resultHigh.newAlerts.first?.type, AlertType.cpuHigh)
        XCTAssertEqual(resultHigh.newAlerts.first?.severity, AlertSeverity.warning)

        // Critical CPU (98%)
        let cpuCritical = CPUMetrics(totalUsage: 98.0, userPercentage: 60.0, systemPercentage: 38.0, idlePercentage: 2.0)
        let metricsCritical = SystemMetrics(cpu: cpuCritical)
        let resultCritical = AlertEvaluator.evaluate(metrics: metricsCritical, config: config, lastFired: firedMap)
        XCTAssertEqual(resultCritical.newAlerts.count, 1)
        XCTAssertEqual(resultCritical.newAlerts.first?.type, AlertType.cpuHigh)
        XCTAssertEqual(resultCritical.newAlerts.first?.severity, AlertSeverity.critical)
    }

    func testMemoryPressureEvaluation() {
        let config = AlertConfiguration(memoryPressureAlertsEnabled: true, cooldownInterval: 60)
        let firedMap: [AlertType: Date] = [:]

        // Warning pressure
        let memWarning = MemoryMetrics(
            totalBytes: 16 * 1024 * 1024 * 1024,
            appMemoryBytes: 10 * 1024 * 1024 * 1024,
            wiredBytes: 2 * 1024 * 1024 * 1024,
            compressedBytes: 2 * 1024 * 1024 * 1024,
            cachedBytes: 1 * 1024 * 1024 * 1024,
            freeBytes: 1 * 1024 * 1024 * 1024,
            pressureLevel: .warning
        )
        let metricsWarning = SystemMetrics(memory: memWarning)
        let resultWarning = AlertEvaluator.evaluate(metrics: metricsWarning, config: config, lastFired: firedMap)
        XCTAssertEqual(resultWarning.newAlerts.count, 1)
        XCTAssertEqual(resultWarning.newAlerts.first?.type, AlertType.memoryPressure)
        XCTAssertEqual(resultWarning.newAlerts.first?.severity, AlertSeverity.warning)

        // Critical pressure
        let memCritical = MemoryMetrics(
            totalBytes: 16 * 1024 * 1024 * 1024,
            appMemoryBytes: 11 * 1024 * 1024 * 1024,
            wiredBytes: 2 * 1024 * 1024 * 1024,
            compressedBytes: 2 * 1024 * 1024 * 1024,
            cachedBytes: 500 * 1024 * 1024,
            freeBytes: 500 * 1024 * 1024,
            pressureLevel: .critical
        )
        let metricsCritical = SystemMetrics(memory: memCritical)
        let resultCritical = AlertEvaluator.evaluate(metrics: metricsCritical, config: config, lastFired: firedMap)
        XCTAssertEqual(resultCritical.newAlerts.count, 1)
        XCTAssertEqual(resultCritical.newAlerts.first?.type, AlertType.memoryPressure)
        XCTAssertEqual(resultCritical.newAlerts.first?.severity, AlertSeverity.critical)
    }

    func testThermalThrottleEvaluation() {
        let config = AlertConfiguration(thermalThreshold: 90.0, thermalAlertsEnabled: true, cooldownInterval: 60)
        let firedMap: [AlertType: Date] = [:]

        // Serious thermal state
        let thermalSerious = ThermalMetrics(socDieTemperature: 88.0, thermalState: .serious)
        let metricsSerious = SystemMetrics(thermal: thermalSerious)
        let resultSerious = AlertEvaluator.evaluate(metrics: metricsSerious, config: config, lastFired: firedMap)
        XCTAssertEqual(resultSerious.newAlerts.count, 1)
        XCTAssertEqual(resultSerious.newAlerts.first?.type, AlertType.thermalThrottling)
        XCTAssertEqual(resultSerious.newAlerts.first?.severity, AlertSeverity.warning)

        // Critical thermal state (> 95°C)
        let thermalCritical = ThermalMetrics(socDieTemperature: 98.0, thermalState: .critical)
        let metricsCritical = SystemMetrics(thermal: thermalCritical)
        let resultCritical = AlertEvaluator.evaluate(metrics: metricsCritical, config: config, lastFired: firedMap)
        XCTAssertEqual(resultCritical.newAlerts.count, 1)
        XCTAssertEqual(resultCritical.newAlerts.first?.type, AlertType.thermalThrottling)
        XCTAssertEqual(resultCritical.newAlerts.first?.severity, AlertSeverity.critical)
    }

    func testCooldownSuppression() {
        let config = AlertConfiguration(cpuThreshold: 90.0, cpuAlertsEnabled: true, cooldownInterval: 60)
        let t0 = Date()

        let cpuHigh = CPUMetrics(totalUsage: 95.0, userPercentage: 50.0, systemPercentage: 45.0, idlePercentage: 5.0)
        let metricsHigh = SystemMetrics(cpu: cpuHigh)

        // Trigger alert at t0
        let result0 = AlertEvaluator.evaluate(metrics: metricsHigh, config: config, lastFired: [:], now: t0)
        XCTAssertEqual(result0.newAlerts.count, 1)
        let updatedFired = result0.updatedFired

        // 10 seconds later: still high CPU, but cooldown should suppress re-trigger
        let t1 = t0.addingTimeInterval(10)
        let result1 = AlertEvaluator.evaluate(metrics: metricsHigh, config: config, lastFired: updatedFired, now: t1)
        XCTAssertTrue(result1.newAlerts.isEmpty, "Alert should be suppressed by cooldown interval")

        // 61 seconds later: cooldown expired, alert can trigger again
        let t2 = t0.addingTimeInterval(61)
        let result2 = AlertEvaluator.evaluate(metrics: metricsHigh, config: config, lastFired: updatedFired, now: t2)
        XCTAssertEqual(result2.newAlerts.count, 1, "Alert should trigger again after cooldown interval passes")
    }
}
