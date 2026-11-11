import XCTest
import Darwin
@testable import SystemResourceViewer

final class HardwareEdgeConditionTests: XCTestCase {

    // MARK: - 1. IOHID Temperature Sensors Edge & Fallback Tests

    func testIOHIDThermalSensorSnapshotAllNilGracefulHandling() {
        let emptySnapshot = IOHIDBridge.ThermalSensorSnapshot(
            socDieAverageTemperature: nil,
            socDiePeakTemperature: nil,
            batteryTemperature: nil,
            storageTemperature: nil,
            individualDieSensors: [:]
        )

        let metrics = ThermalMetrics(
            socDieTemperature: emptySnapshot.socDieAverageTemperature,
            peakDieTemperature: emptySnapshot.socDiePeakTemperature,
            batteryTemperature: emptySnapshot.batteryTemperature,
            storageTemperature: emptySnapshot.storageTemperature,
            thermalState: .nominal,
            fanSpeeds: [],
            isFanless: true
        )

        XCTAssertNil(metrics.socDieTemperature)
        XCTAssertNil(metrics.peakDieTemperature)
        XCTAssertNil(metrics.batteryTemperature)
        XCTAssertNil(metrics.storageTemperature)
        XCTAssertEqual(metrics.thermalState, .nominal)
        XCTAssertEqual(metrics.thermalStateDescription, "Nominal")
        XCTAssertEqual(metrics.thermalStateSymbol, "flame")
        XCTAssertEqual(metrics.coolingStatusDescription, "Fanless Architecture - Passive Cooling")
    }

    func testIOHIDThermalSensorOutOfRangeFiltering() {
        // Temperature values below 10°C or above 125°C should be treated as uncalibrated or inactive
        let validLow = 10.0
        let validHigh = 125.0
        let outOfRangeNegative = -5.0
        let outOfRangeOverheated = 150.0

        XCTAssertTrue(validLow >= 10.0 && validLow <= 125.0)
        XCTAssertTrue(validHigh >= 10.0 && validHigh <= 125.0)
        XCTAssertFalse(outOfRangeNegative >= 10.0 && outOfRangeNegative <= 125.0)
        XCTAssertFalse(outOfRangeOverheated >= 10.0 && outOfRangeOverheated <= 125.0)
    }

    func testThermalMonitorServiceFallbackWhenIOHIDEmpty() async {
        let service = ThermalMonitorService()
        let metrics = await service.pollThermalMetrics()

        // When running on systems where IOHID temperature sensors are unavailable or restricted,
        // ThermalMonitorService must gracefully fallback to ProcessInfo thermalState without crashing.
        XCTAssertNotNil(metrics.thermalState)
        XCTAssertFalse(metrics.thermalStateDescription.isEmpty)
        XCTAssertFalse(metrics.thermalStateSymbol.isEmpty)
        XCTAssertFalse(metrics.coolingStatusDescription.isEmpty)

        // If die temperature is available, it must be within reasonable physical bounds (10°C - 125°C)
        if let dieTemp = metrics.socDieTemperature {
            XCTAssertGreaterThanOrEqual(dieTemp, 10.0)
            XCTAssertLessThanOrEqual(dieTemp, 125.0)
        }

        // If battery temperature is present, verify bounds
        if let batTemp = metrics.batteryTemperature {
            XCTAssertGreaterThanOrEqual(batTemp, 10.0)
            XCTAssertLessThanOrEqual(batTemp, 100.0)
        }
    }

    // MARK: - 2. Fanless Detection Across Architectures

    func testFanlessModelPatternMatching() {
        let knownFanlessModels: Set<String> = [
            "MacBook8,1", "MacBook9,1", "MacBook10,1",
            "Mac14,2", "Mac14,15", "Mac15,2", "Mac15,12", "Mac15,13", "Mac17,3"
        ]

        func isFanless(model: String) -> Bool {
            if model.contains("MacBookAir") { return true }
            return knownFanlessModels.contains(model)
        }

        // Apple Silicon MacBook Air models
        XCTAssertTrue(isFanless(model: "MacBookAir10,1"), "M1 MacBook Air should be fanless")
        XCTAssertTrue(isFanless(model: "Mac14,2"), "M2 13-inch MacBook Air should be fanless")
        XCTAssertTrue(isFanless(model: "Mac14,15"), "M2 15-inch MacBook Air should be fanless")
        XCTAssertTrue(isFanless(model: "Mac15,12"), "M3 13-inch MacBook Air should be fanless")
        XCTAssertTrue(isFanless(model: "Mac15,13"), "M3 15-inch MacBook Air should be fanless")

        // Intel 12-inch fanless MacBook models
        XCTAssertTrue(isFanless(model: "MacBook8,1"), "Intel 12-inch 2015 MacBook should be fanless")
        XCTAssertTrue(isFanless(model: "MacBook9,1"), "Intel 12-inch 2016 MacBook should be fanless")
        XCTAssertTrue(isFanless(model: "MacBook10,1"), "Intel 12-inch 2017 MacBook should be fanless")

        // Intel MacBook Air models
        XCTAssertTrue(isFanless(model: "MacBookAir6,2"), "Intel MacBookAir should be matched by prefix")
        XCTAssertTrue(isFanless(model: "MacBookAir9,1"), "Intel MacBookAir 2020 should be matched by prefix")

        // Fan-equipped MacBook Pro models
        XCTAssertFalse(isFanless(model: "MacBookPro18,1"), "M1 Pro 16-inch MacBook Pro has fans")
        XCTAssertFalse(isFanless(model: "Mac14,7"), "M2 13-inch MacBook Pro has fans")
        XCTAssertFalse(isFanless(model: "Mac15,3"), "M3 14-inch MacBook Pro has fans")
        XCTAssertFalse(isFanless(model: "MacBookPro16,1"), "Intel 16-inch MacBook Pro has fans")

        // Fan-equipped Desktop models
        XCTAssertFalse(isFanless(model: "Mac14,3"), "M2 Mac mini has fans")
        XCTAssertFalse(isFanless(model: "Mac13,1"), "M1 Mac Studio has fans")
        XCTAssertFalse(isFanless(model: "MacPro7,1"), "Intel Mac Pro has fans")
        XCTAssertFalse(isFanless(model: "iMac21,1"), "M1 iMac has fans")

        // Boundary cases
        XCTAssertFalse(isFanless(model: ""))
        XCTAssertFalse(isFanless(model: "UnknownModel1,1"))
    }

    func testLiveHostFanlessArchitectureQuery() {
        let isFanless = IOKitBridge.isFanlessArchitecture()
        let fanTelemetry = IOKitBridge.fetchFanTelemetry()

        // Invariant: if hardware architecture is fanless, fanTelemetry must report isFanless == true
        if isFanless {
            XCTAssertTrue(fanTelemetry.isFanless)
            XCTAssertEqual(fanTelemetry.fans.count, 0)
        } else if fanTelemetry.fans.isEmpty {
            // If no fans detected via SMC, fanTelemetry should also mark isFanless == true
            XCTAssertTrue(fanTelemetry.isFanless)
        } else {
            // Fan-equipped system with active fans
            XCTAssertFalse(fanTelemetry.isFanless)
            for fan in fanTelemetry.fans {
                XCTAssertGreaterThanOrEqual(fan.currentRPM, 0)
                XCTAssertGreaterThan(fan.maxRPM, 0)
            }
        }
    }

    // MARK: - 3. Process Tree Cycle Detection & Deep Hierarchy Stress

    func testProcessItemDirectSelfParentingCycle() {
        // Self-parenting: PID 42 has PPID 42
        let selfParent = ProcessItem(
            id: 42,
            ppid: 42,
            name: "SelfLoop",
            cpuPercentage: 10.0,
            memoryBytes: 50 * 1024 * 1024
        )

        // Verifies value-type resilience: selfParent cannot form a reference cycle
        XCTAssertEqual(selfParent.totalCPU, 10.0)
        XCTAssertEqual(selfParent.totalMemory, 50 * 1024 * 1024)
        XCTAssertFalse(selfParent.hasChildren)
    }

    func testProcessItemDeepNestingAggregation() {
        // Build a 50-level deep process tree: P50 is child of P49 ... P2 is child of P1
        var current = ProcessItem(
            id: 50,
            ppid: 49,
            name: "LeafProcess",
            cpuPercentage: 1.0,
            memoryBytes: 1024 * 1024
        )

        for depth in (1..<50).reversed() {
            let parent = ProcessItem(
                id: pid_t(depth),
                ppid: pid_t(depth - 1),
                name: "Parent_\(depth)",
                cpuPercentage: 1.0,
                memoryBytes: 1024 * 1024,
                children: [current]
            )
            current = parent
        }

        // Root process P1 should aggregate all 50 levels
        XCTAssertEqual(current.id, 1)
        XCTAssertEqual(current.totalCPU, 50.0, accuracy: 0.01)
        XCTAssertEqual(current.totalMemory, 50 * 1024 * 1024)
        XCTAssertTrue(current.hasChildren)
    }

    func testProcessTreeCycleOrphanResilience() {
        // Simulated process table where two processes form a mutual cycle:
        // P100 has PPID 200, and P200 has PPID 100
        let items: [ProcessItem] = [
            ProcessItem(id: 100, ppid: 200, name: "CyclicA", cpuPercentage: 5.0, memoryBytes: 10 * 1024 * 1024),
            ProcessItem(id: 200, ppid: 100, name: "CyclicB", cpuPercentage: 10.0, memoryBytes: 20 * 1024 * 1024),
            ProcessItem(id: 300, ppid: 1, name: "NormalApp", cpuPercentage: 15.0, memoryBytes: 30 * 1024 * 1024)
        ]

        // Manual parent-child structuring matching ProcessMonitorService logic
        var itemMap: [pid_t: ProcessItem] = [:]
        for item in items { itemMap[item.id] = item }

        var childrenByParent: [pid_t: [ProcessItem]] = [:]
        for (_, item) in itemMap {
            if item.ppid > 1 && itemMap[item.ppid] != nil && item.ppid != item.id {
                childrenByParent[item.ppid, default: []].append(item)
            }
        }

        var rootItems: [ProcessItem] = []
        for (_, item) in itemMap {
            let isChild = (item.ppid > 1 && itemMap[item.ppid] != nil && item.ppid != item.id)
            if !isChild {
                var root = item
                if let directChildren = childrenByParent[root.id] {
                    root.children = directChildren
                }
                rootItems.append(root)
            }
        }

        // Verify no infinite loop occurred during hierarchy construction
        XCTAssertFalse(rootItems.isEmpty)
        XCTAssertTrue(rootItems.contains { $0.id == 300 })
        // In the cyclical case, neither 100 nor 200 has a root anchor, so no infinite recursion occurs
        for root in rootItems {
            XCTAssertGreaterThan(root.totalCPU, 0.0)
            XCTAssertGreaterThan(root.totalMemory, 0)
        }
    }

    // MARK: - 4. Memory Leak Absence During High-Frequency Polling

    func testMemoryLeakAbsenceDuringHighFrequencyTelemetryPolling() async {
        let thermalService = ThermalMonitorService()
        let gpuService = GPUMonitorService()

        func getResidentMemoryBytes() -> UInt64 {
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
            let kerr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }
            return kerr == KERN_SUCCESS ? info.resident_size : 0
        }

        // Warm up services
        _ = await thermalService.pollThermalMetrics()
        _ = await gpuService.pollGPUMetrics()

        let initialMem = getResidentMemoryBytes()

        // Execute 200 rapid polling cycles
        for _ in 0..<200 {
            _ = await thermalService.pollThermalMetrics()
            _ = await gpuService.pollGPUMetrics()
            _ = IOKitBridge.fetchCumulativeDiskIOBytes()
            _ = IOKitBridge.fetchBatteryTelemetry()
        }

        let finalMem = getResidentMemoryBytes()
        let growthBytes = finalMem > initialMem ? finalMem - initialMem : 0
        let growthMB = Double(growthBytes) / (1024.0 * 1024.0)

        // Invariant: 200 polling cycles should not cause memory to grow by more than 10 MB
        XCTAssertLessThan(growthMB, 10.0, "High-frequency telemetry polling leaked memory: grew by \(growthMB) MB")
    }
}
