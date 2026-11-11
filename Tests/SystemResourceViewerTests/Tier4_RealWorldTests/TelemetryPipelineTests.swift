import XCTest
@testable import SystemResourceViewer

final class TelemetryPipelineTests: XCTestCase {

    func testLiveTelemetryEndToEndPipeline() async {
        let scheduler = MetricsScheduler(interval: 0.1)
        let stream = await scheduler.metricsStream()

        var receivedSnapshots = 0
        for await snapshot in stream {
            receivedSnapshots += 1

            // Verify live Mach CPU metrics
            XCTAssertGreaterThanOrEqual(snapshot.cpu.totalUsage, 0.0)
            XCTAssertLessThanOrEqual(snapshot.cpu.totalUsage, 100.0)
            XCTAssertGreaterThan(snapshot.cpu.pCoreCount, 0)

            // Verify live Darwin Memory metrics
            XCTAssertGreaterThan(snapshot.memory.totalBytes, 1024 * 1024 * 1024)
            XCTAssertGreaterThan(snapshot.memory.usedBytes, 0)
            XCTAssertGreaterThanOrEqual(snapshot.memory.usedPercentage, 0.0)

            // Verify live Disk metrics
            XCTAssertGreaterThan(snapshot.disk.totalBytes, 0)

            // Verify live Network metrics
            XCTAssertFalse(snapshot.network.primaryInterfaceName.isEmpty)

            // Verify live Power & Thermal metrics
            XCTAssertNotNil(snapshot.power.thermalState)
            XCTAssertNotNil(snapshot.thermal.thermalState)

            // Verify live GPU metrics
            XCTAssertGreaterThanOrEqual(snapshot.gpu.deviceUtilization, 0.0)
            XCTAssertLessThanOrEqual(snapshot.gpu.deviceUtilization, 100.0)
            XCTAssertFalse(snapshot.gpu.modelName.isEmpty)

            // Verify active processes
            XCTAssertFalse(snapshot.processes.isEmpty)

            if receivedSnapshots >= 2 {
                break
            }
        }

        await scheduler.stop()
        XCTAssertGreaterThanOrEqual(receivedSnapshots, 2)
    }

    func testProcessTreeHierarchyIntegrity() async {
        let topo = DarwinMachBridge.fetchCPUTopology()
        let processService = ProcessMonitorService()
        let result = await processService.pollProcesses(coreCount: topo.totalCores)

        XCTAssertFalse(result.allProcesses.isEmpty)
        XCTAssertLessThanOrEqual(result.topCPU.count, 5)
        XCTAssertLessThanOrEqual(result.topMemory.count, 5)

        // Verify parent-child relationship: no process is its own child
        for proc in result.allProcesses {
            XCTAssertFalse(proc.architecture.isEmpty)
            XCTAssertFalse(proc.ownerUser.isEmpty)
            XCTAssertGreaterThanOrEqual(proc.threadCount, 0)
            for child in proc.children {
                XCTAssertNotEqual(proc.id, child.id)
                XCTAssertEqual(child.ppid, proc.id)
            }
        }
    }
}
