import XCTest
@testable import SystemResourceViewer

final class CPUBoundaryTests: XCTestCase {

    func testZeroPercentUtilizationBound() {
        let metrics = CPUMetrics(
            totalUsage: 0.0,
            userPercentage: 0.0,
            systemPercentage: 0.0,
            idlePercentage: 100.0
        )
        XCTAssertEqual(metrics.totalUsage, 0.0)
        XCTAssertEqual(metrics.idlePercentage, 100.0)
    }

    func testOneHundredPercentSaturatedBound() {
        let metrics = CPUMetrics(
            totalUsage: 100.0,
            userPercentage: 70.0,
            systemPercentage: 30.0,
            idlePercentage: 0.0
        )
        XCTAssertEqual(metrics.totalUsage, 100.0)
        XCTAssertEqual(metrics.idlePercentage, 0.0)
    }

    func testSingleCoreTopologyHandling() {
        let singleCoreMetrics = CPUMetrics(
            totalUsage: 25.0,
            coreUsages: [
                CoreUsage(coreIndex: 0, type: .performance, totalUsage: 25.0, userUsage: 15.0, systemUsage: 10.0, idleUsage: 75.0)
            ],
            pCoreCount: 1,
            eCoreCount: 0
        )
        XCTAssertEqual(singleCoreMetrics.pCoreCount, 1)
        XCTAssertEqual(singleCoreMetrics.eCoreCount, 0)
        XCTAssertEqual(singleCoreMetrics.coreUsages.count, 1)
        XCTAssertEqual(singleCoreMetrics.coreUsages[0].type, .performance)
    }

    func testZeroDeltaTicksCalculationResilience() async {
        let service = CPUMonitorService()
        // Calling twice in immediate sub-millisecond succession
        _ = await service.pollCPUMetrics(topProcesses: [])
        let immediate = await service.pollCPUMetrics(topProcesses: [])

        XCTAssertGreaterThanOrEqual(immediate.totalUsage, 0.0)
        XCTAssertLessThanOrEqual(immediate.totalUsage, 100.0)
        XCTAssertGreaterThanOrEqual(immediate.idlePercentage, 0.0)
        XCTAssertLessThanOrEqual(immediate.idlePercentage, 100.0)
    }

    func testAsymmetricHybridTopologyIndexing() {
        let topo = DarwinMachBridge.fetchCPUTopology()
        XCTAssertGreaterThanOrEqual(topo.totalCores, topo.performanceCores)
        if topo.efficiencyCores > 0 {
            XCTAssertEqual(topo.totalCores, topo.performanceCores + topo.efficiencyCores)
        }
    }
}
