import XCTest
@testable import SystemResourceViewer

final class CPUMetricsTests: XCTestCase {

    func testCPUMetricsInitializationDefaultEmpty() {
        let metrics = CPUMetrics.empty
        XCTAssertEqual(metrics.totalUsage, 0.0)
        XCTAssertEqual(metrics.userPercentage, 0.0)
        XCTAssertEqual(metrics.systemPercentage, 0.0)
        XCTAssertEqual(metrics.idlePercentage, 100.0)
        XCTAssertEqual(metrics.pCoreAverageUsage, 0.0)
        XCTAssertEqual(metrics.eCoreAverageUsage, 0.0)
        XCTAssertTrue(metrics.coreUsages.isEmpty)
        XCTAssertTrue(metrics.topProcesses.isEmpty)
    }

    func testCoreUsageInitialization() {
        let usage = CoreUsage(
            coreIndex: 2,
            type: .performance,
            totalUsage: 45.5,
            userUsage: 30.0,
            systemUsage: 15.5,
            idleUsage: 54.5
        )
        XCTAssertEqual(usage.id, 2)
        XCTAssertEqual(usage.coreIndex, 2)
        XCTAssertEqual(usage.type, .performance)
        XCTAssertEqual(usage.totalUsage, 45.5, accuracy: 0.01)
        XCTAssertEqual(usage.userUsage, 30.0, accuracy: 0.01)
        XCTAssertEqual(usage.systemUsage, 15.5, accuracy: 0.01)
        XCTAssertEqual(usage.idleUsage, 54.5, accuracy: 0.01)
    }

    func testCoreTypeLabels() {
        XCTAssertEqual(CoreType.performance.shortLabel, "P")
        XCTAssertEqual(CoreType.efficiency.shortLabel, "E")
        XCTAssertEqual(CoreType.performance.rawValue, "Performance")
        XCTAssertEqual(CoreType.efficiency.rawValue, "Efficiency")
    }

    func testCPUMonitorServiceInitialBaseline() async {
        let service = CPUMonitorService()
        let initial = await service.pollCPUMetrics(topProcesses: [])
        XCTAssertEqual(initial.totalUsage, 0.0)
        XCTAssertEqual(initial.idlePercentage, 100.0)
        XCTAssertGreaterThan(initial.pCoreCount + initial.eCoreCount, 0)
        XCTAssertEqual(initial.coreUsages.count, initial.pCoreCount + initial.eCoreCount)
    }

    func testCPUMonitorServiceDeltaSampling() async {
        let service = CPUMonitorService()
        _ = await service.pollCPUMetrics(topProcesses: [])

        // Perform small work
        var dummy = 0
        for i in 0..<100_000 { dummy += (i % 7) }
        _ = dummy

        let second = await service.pollCPUMetrics(topProcesses: [])
        XCTAssertGreaterThanOrEqual(second.totalUsage, 0.0)
        XCTAssertLessThanOrEqual(second.totalUsage, 100.0)
        XCTAssertGreaterThanOrEqual(second.idlePercentage, 0.0)
        XCTAssertLessThanOrEqual(second.idlePercentage, 100.0)
        XCTAssertEqual(second.coreUsages.count, second.pCoreCount + second.eCoreCount)
    }

    func testDarwinMachBridgeCPUTopology() {
        let topo = DarwinMachBridge.fetchCPUTopology()
        XCTAssertGreaterThan(topo.totalCores, 0)
        XCTAssertGreaterThan(topo.performanceCores, 0)
        XCTAssertGreaterThanOrEqual(topo.efficiencyCores, 0)
        XCTAssertEqual(topo.totalCores, topo.performanceCores + topo.efficiencyCores)
    }
}
