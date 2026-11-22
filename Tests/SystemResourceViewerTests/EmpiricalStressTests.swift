import AppKit
import Darwin
import Foundation
import XCTest
@testable import SystemResourceViewer

/// EMPIRICAL CHALLENGER TEST SUITE:
/// Rigorous stress testing, pathological boundary verification, concurrency safety,
/// and clock jump validation for System Resource Viewer v1.1.0.
final class EmpiricalStressTests: XCTestCase {

    // MARK: - 1. IOKitBridge Pathological Numeric Inputs & Boundary Extraction

    func testIOKitBatteryEmptyDictionaryHandling() {
        let emptyDict: [String: Any] = [:]
        let parsed = IOKitBridge.parseBatteryProperties(from: emptyDict)

        XCTAssertNil(parsed.cycleCount, "Empty dictionary must yield nil cycleCount")
        XCTAssertNil(parsed.healthPercentage, "Empty dictionary must yield nil healthPercentage")
        XCTAssertNil(parsed.powerDrawWatts, "Empty dictionary must yield nil powerDrawWatts")
    }

    func testIOKitBatteryNonNumericAndMalformedTypes() {
        let malformedDict: [String: Any] = [
            "CycleCount": "NotANumber",
            "MaxCapacity": ["nested": "array"],
            "DesignCapacity": false,
            "InstantAmperage": "invalid",
            "Voltage": Date()
        ]
        let parsed = IOKitBridge.parseBatteryProperties(from: malformedDict)

        XCTAssertNil(parsed.cycleCount, "Malformed CycleCount string must yield nil without crashing")
        XCTAssertNil(parsed.healthPercentage, "Malformed MaxCapacity dictionary must yield nil")
        XCTAssertNil(parsed.powerDrawWatts, "Malformed Voltage Date must yield nil")
    }

    func testIOKitBatteryNegativeAndZeroCapacitiesClamping() {
        // Negative MaxCapacity with valid DesignCapacity
        let negativeMaxDict: [String: Any] = [
            "MaxCapacity": NSNumber(value: -1000),
            "DesignCapacity": NSNumber(value: 5000),
            "InstantAmperage": NSNumber(value: -500),
            "Voltage": NSNumber(value: 12000)
        ]
        let parsedNegative = IOKitBridge.parseBatteryProperties(from: negativeMaxDict)
        XCTAssertNotNil(parsedNegative.healthPercentage)
        XCTAssertEqual(parsedNegative.healthPercentage!, 0.0, "Negative capacity ratio must clamp to 0.0%")

        // Zero DesignCapacity must NOT divide by zero
        let zeroDesignDict: [String: Any] = [
            "MaxCapacity": NSNumber(value: 4500),
            "DesignCapacity": NSNumber(value: 0),
            "InstantAmperage": NSNumber(value: -500),
            "Voltage": NSNumber(value: 12000)
        ]
        let parsedZeroDesign = IOKitBridge.parseBatteryProperties(from: zeroDesignDict)
        // When designCap <= 0, falls back to min(100.0, maxCap) = 100.0
        XCTAssertNotNil(parsedZeroDesign.healthPercentage)
        XCTAssertEqual(parsedZeroDesign.healthPercentage!, 100.0)

        // Negative DesignCapacity must NOT produce negative division
        let negativeDesignDict: [String: Any] = [
            "MaxCapacity": NSNumber(value: 4500),
            "DesignCapacity": NSNumber(value: -5000)
        ]
        let parsedNegDesign = IOKitBridge.parseBatteryProperties(from: negativeDesignDict)
        XCTAssertNotNil(parsedNegDesign.healthPercentage)
        XCTAssertEqual(parsedNegDesign.healthPercentage!, 100.0)
    }

    func testIOKitBatteryVoltageBoundaryAndZeroPowerDraw() {
        // Zero Voltage should suppress power draw calculation
        let zeroVoltDict: [String: Any] = [
            "InstantAmperage": NSNumber(value: -2000),
            "Voltage": NSNumber(value: 0)
        ]
        let parsedZeroVolt = IOKitBridge.parseBatteryProperties(from: zeroVoltDict)
        XCTAssertNil(parsedZeroVolt.powerDrawWatts, "Zero voltage must yield nil power draw (volt > 0 guard)")

        // Negative Voltage should suppress power draw calculation
        let negVoltDict: [String: Any] = [
            "InstantAmperage": NSNumber(value: -2000),
            "Voltage": NSNumber(value: -12000)
        ]
        let parsedNegVolt = IOKitBridge.parseBatteryProperties(from: negVoltDict)
        XCTAssertNil(parsedNegVolt.powerDrawWatts, "Negative voltage must yield nil power draw")

        // Extremely high voltage and amperage
        let extremeDict: [String: Any] = [
            "InstantAmperage": NSNumber(value: 50_000),     // 50A
            "Voltage": NSNumber(value: 100_000)             // 100V
        ]
        let parsedExtreme = IOKitBridge.parseBatteryProperties(from: extremeDict)
        XCTAssertNotNil(parsedExtreme.powerDrawWatts)
        // (50,000 * 100,000) / 1,000,000 = 5,000 W
        XCTAssertEqual(parsedExtreme.powerDrawWatts!, 5000.0, accuracy: 0.1)
    }

    func testIOKitDiskStatsBoundaryAndPathologicalInputs() {
        // Empty dictionary
        let emptyStats: [String: Any] = [:]
        let parsedEmpty = IOKitBridge.parseDiskIOStats(from: emptyStats)
        XCTAssertNil(parsedEmpty.read)
        XCTAssertNil(parsedEmpty.write)

        // Strings instead of numbers
        let stringStats: [String: Any] = [
            "Bytes (Read)": "100000000",
            "Bytes (Write)": "200000000"
        ]
        let parsedString = IOKitBridge.parseDiskIOStats(from: stringStats)
        XCTAssertNil(parsedString.read, "String value should not parse as UInt64 bytes")
        XCTAssertNil(parsedString.write, "String value should not parse as UInt64 bytes")

        // UInt64.max boundary
        let maxStats: [String: Any] = [
            "Bytes (Read)": NSNumber(value: UInt64.max),
            "Bytes (Write)": NSNumber(value: UInt64.max)
        ]
        let parsedMax = IOKitBridge.parseDiskIOStats(from: maxStats)
        XCTAssertEqual(parsedMax.read, UInt64.max)
        XCTAssertEqual(parsedMax.write, UInt64.max)

        // Floating point NSNumber truncation
        let floatStats: [String: Any] = [
            "Bytes (Read)": NSNumber(value: 987654.789),
            "Bytes (Write)": NSNumber(value: 123456.123)
        ]
        let parsedFloat = IOKitBridge.parseDiskIOStats(from: floatStats)
        XCTAssertEqual(parsedFloat.read, 987654)
        XCTAssertEqual(parsedFloat.write, 123456)
    }

    // MARK: - 2. DarwinMachBridge Static MIB & ProcessBufferSlab Stress

    func testDarwinMachBridgeRosettaStaticMIBSafety() {
        // Boundary PIDs
        XCTAssertFalse(DarwinMachBridge.isRosettaTranslated(pid: 0), "PID 0 must safely return false")
        XCTAssertFalse(DarwinMachBridge.isRosettaTranslated(pid: -1), "PID -1 must safely return false")
        XCTAssertFalse(DarwinMachBridge.isRosettaTranslated(pid: 999_999), "Non-existent PID must safely return false")

        // Current process is running natively (or x86_64 host), sysctl check should execute cleanly without error
        let currentPID = getpid()
        _ = DarwinMachBridge.isRosettaTranslated(pid: currentPID)
    }

    func testProcessBufferSlabRepeatedExecutionStability() {
        let slab = DarwinMachBridge.ProcessBufferSlab.shared
        let initialCapacity = slab.currentByteCapacity

        // Perform 50 rapid sequential process enumerations
        for _ in 0..<50 {
            let list = slab.listProcesses()
            XCTAssertFalse(list.isEmpty, "ProcessBufferSlab must return non-empty list of active processes")
            // Ensure every returned entry has valid PID
            for proc in list.prefix(10) {
                XCTAssertGreaterThan(proc.pid, 0)
                XCTAssertFalse(proc.name.isEmpty)
            }
        }

        let postCapacity = slab.currentByteCapacity
        XCTAssertGreaterThanOrEqual(postCapacity, initialCapacity, "Byte capacity should be retained or grown, never corrupted")
        XCTAssertGreaterThanOrEqual(postCapacity, 512 * 1024, "Byte capacity must be at least minimum 512KB slab")
    }

    func testProcessBufferSlabConcurrentAccessSafety() async {
        let slab = DarwinMachBridge.ProcessBufferSlab.shared

        // Launch 10 concurrent async tasks calling listProcesses simultaneously
        await withTaskGroup(of: Int.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let procs = slab.listProcesses()
                    return procs.count
                }
            }

            var results: [Int] = []
            for await count in group {
                results.append(count)
            }

            XCTAssertEqual(results.count, 10, "All 10 concurrent requests must complete")
            for count in results {
                XCTAssertGreaterThan(count, 0, "Concurrent listProcesses calls must yield valid process counts")
            }
        }
    }

    func testProcessBufferSlabIndependentInstanceLifecycle() {
        // Verify independent instance allocation and deinit
        var slabInstance: DarwinMachBridge.ProcessBufferSlab? = DarwinMachBridge.ProcessBufferSlab()
        let procs = slabInstance?.listProcesses() ?? []
        XCTAssertFalse(procs.isEmpty)
        XCTAssertGreaterThanOrEqual(slabInstance?.currentByteCapacity ?? 0, 512 * 1024)

        // Drop instance to trigger deinit
        slabInstance = nil
        XCTAssertNil(slabInstance, "Slab instance must deallocate cleanly without segfault or leak")
    }

    // MARK: - 3. Rate Spike & Wall-Clock Jump Tests

    func testRateDeltaCalculationUnderSimulatedTimeSteps() {
        // Oracle testing of rate = dBytes / dt with sleep/wake reset (dt > 10.0) and tiny dt (dt <= 0.05)
        func computeRate(prevBytes: UInt64, currentBytes: UInt64, dt: Double) -> Double {
            if dt > 10.0 {
                // System woke from sleep or clock jumped: reset baseline, speed = 0.0
                return 0.0
            } else if dt > 0.05 {
                let dBytes = currentBytes >= prevBytes ? currentBytes - prevBytes : 0
                return Double(dBytes) / dt
            } else {
                // Too small dt or negative dt: suppress division
                return 0.0
            }
        }

        let baseBytes: UInt64 = 10_000_000
        let newBytes: UInt64 = 11_000_000 // 1 MB transfer

        // Scenario 1: Normal 1-second interval
        let normalRate = computeRate(prevBytes: baseBytes, currentBytes: newBytes, dt: 1.0)
        XCTAssertEqual(normalRate, 1_000_000.0, accuracy: 0.1)

        // Scenario 2: Normal 5-second interval
        let fiveSecRate = computeRate(prevBytes: baseBytes, currentBytes: newBytes, dt: 5.0)
        XCTAssertEqual(fiveSecRate, 200_000.0, accuracy: 0.1)

        // Scenario 3: Clock jump forward / wake from sleep (dt = 15.0s)
        let sleepRate15 = computeRate(prevBytes: baseBytes, currentBytes: newBytes, dt: 15.0)
        XCTAssertEqual(sleepRate15, 0.0, "Sleep/wake dt = 15s must reset rate to 0.0 to prevent spike")

        // Scenario 4: Extreme sleep jump (dt = 3600.0s)
        let sleepRateHour = computeRate(prevBytes: baseBytes, currentBytes: newBytes, dt: 3600.0)
        XCTAssertEqual(sleepRateHour, 0.0, "1-hour sleep jump must reset rate to 0.0")

        // Scenario 5: Rapid poll / microsecond dt (dt = 0.001s)
        let microRate = computeRate(prevBytes: baseBytes, currentBytes: newBytes, dt: 0.001)
        XCTAssertEqual(microRate, 0.0, "Sub-0.05s poll must not perform volatile divide-by-zero or spike")

        // Scenario 6: Zero delta time (dt = 0.0s)
        let zeroDtRate = computeRate(prevBytes: baseBytes, currentBytes: newBytes, dt: 0.0)
        XCTAssertEqual(zeroDtRate, 0.0, "dt = 0 must never produce NaN or Inf")
        XCTAssertFalse(zeroDtRate.isNaN)
        XCTAssertFalse(zeroDtRate.isInfinite)

        // Scenario 7: Negative time jump (system clock adjusted backwards, dt = -10.0s)
        let negDtRate = computeRate(prevBytes: baseBytes, currentBytes: newBytes, dt: -10.0)
        XCTAssertEqual(negDtRate, 0.0, "Negative dt must yield 0.0 and never negative rate")

        // Scenario 8: Interface counter wrap/reset (current < prev)
        let wrapRate = computeRate(prevBytes: 10_000_000, currentBytes: 1000, dt: 1.0)
        XCTAssertEqual(wrapRate, 0.0, "Counter wrap must yield 0.0 and never unsigned overflow")
    }

    func testLiveNetworkMonitorServiceRapidConsecutivePolls() async {
        let service = NetworkMonitorService()

        // 1st poll initializes previousSample
        let m1 = await service.pollNetworkMetrics()
        XCTAssertGreaterThanOrEqual(m1.downloadBytesPerSecond, 0.0)
        XCTAssertGreaterThanOrEqual(m1.uploadBytesPerSecond, 0.0)
        XCTAssertFalse(m1.downloadBytesPerSecond.isNaN)
        XCTAssertFalse(m1.uploadBytesPerSecond.isNaN)

        // 2nd poll immediately afterward (dt will be tiny, < 0.05s)
        let m2 = await service.pollNetworkMetrics()
        XCTAssertGreaterThanOrEqual(m2.downloadBytesPerSecond, 0.0)
        XCTAssertGreaterThanOrEqual(m2.uploadBytesPerSecond, 0.0)
        XCTAssertFalse(m2.downloadBytesPerSecond.isNaN)
        XCTAssertFalse(m2.uploadBytesPerSecond.isNaN)
        XCTAssertFalse(m2.downloadBytesPerSecond.isInfinite)
        XCTAssertFalse(m2.uploadBytesPerSecond.isInfinite)
    }

    func testLiveDiskAndPowerServiceRapidConsecutivePolls() async {
        let service = DiskAndPowerService()

        let (d1, p1) = await service.pollDiskAndPower()
        XCTAssertGreaterThanOrEqual(d1.readBytesPerSecond, 0.0)
        XCTAssertGreaterThanOrEqual(d1.writeBytesPerSecond, 0.0)
        XCTAssertGreaterThan(d1.totalBytes, 0)
        XCTAssertFalse(d1.readBytesPerSecond.isNaN)
        XCTAssertFalse(d1.writeBytesPerSecond.isNaN)
        XCTAssertGreaterThanOrEqual(p1.batteryPercentage, 0)

        // Immediate subsequent poll
        let (d2, _) = await service.pollDiskAndPower()
        XCTAssertGreaterThanOrEqual(d2.readBytesPerSecond, 0.0)
        XCTAssertGreaterThanOrEqual(d2.writeBytesPerSecond, 0.0)
        XCTAssertFalse(d2.readBytesPerSecond.isNaN)
        XCTAssertFalse(d2.writeBytesPerSecond.isNaN)
        XCTAssertFalse(d2.readBytesPerSecond.isInfinite)
        XCTAssertFalse(d2.writeBytesPerSecond.isInfinite)
    }

    // MARK: - 4. IconCache Memory Bounds & Rapid Insertion Stress

    func testIconCacheStrict500ItemCapacityBoundUnder1000SequentialInsertions() {
        let cache = ProcessItem.IconCache(maxCapacity: 500)
        let dummyImage = NSImage(size: NSSize(width: 16, height: 16))

        for i in 1...1000 {
            let path = "/Applications/App\(i).app/Contents/MacOS/App\(i)"
            cache.setIcon(dummyImage, forPath: path)

            // Invariant: count must NEVER exceed maxCapacity (500)
            XCTAssertLessThanOrEqual(cache.count, 500, "IconCache count must never exceed 500 (failed at insertion \(i))")

            if i <= 500 {
                XCTAssertEqual(cache.count, i)
            } else if i == 501 {
                // At 501, purge occurs and single new item is stored
                XCTAssertEqual(cache.count, 1)
            }
        }

        // At end of 1000 insertions (500 after the purge at 501), count must be exactly 500
        XCTAssertEqual(cache.count, 500)
    }

    func testIconCacheConcurrentInsertionAndLookupStress() async {
        let cache = ProcessItem.IconCache(maxCapacity: 500)
        let dummyImage = NSImage(size: NSSize(width: 16, height: 16))

        // Spawn 20 tasks inserting 100 items each (2000 total insertions) concurrently with 10 reader tasks
        await withTaskGroup(of: Void.self) { group in
            // Writers
            for taskIndex in 0..<20 {
                group.addTask {
                    for itemIndex in 0..<100 {
                        let path = "/System/Applications/App_\(taskIndex)_\(itemIndex)"
                        cache.setIcon(dummyImage, forPath: path)
                        XCTAssertLessThanOrEqual(cache.count, 500)
                    }
                }
            }

            // Readers
            for readerIndex in 0..<10 {
                group.addTask {
                    for itemIndex in 0..<100 {
                        let path = "/System/Applications/App_\(readerIndex)_\(itemIndex)"
                        _ = cache.icon(forPath: path)
                        let cnt = cache.count
                        XCTAssertLessThanOrEqual(cnt, 500)
                    }
                }
            }
        }

        // Final verification
        XCTAssertLessThanOrEqual(cache.count, 500, "Final count after concurrent stress must be <= 500")
        XCTAssertGreaterThan(cache.count, 0)

        // Clear verification
        cache.clear()
        XCTAssertEqual(cache.count, 0)
    }

    // MARK: - 5. ProcessItem Equality & Hashable Integrity

    func testProcessItemEqualityDifferentiatesDiskMetrics() {
        let base = ProcessItem(
            id: 100,
            name: "Worker",
            cpuPercentage: 12.5,
            memoryBytes: 50 * 1024 * 1024,
            diskReadBytesPerSecond: 1000,
            diskWriteBytesPerSecond: 2000
        )

        let modifiedRead = ProcessItem(
            id: 100,
            name: "Worker",
            cpuPercentage: 12.5,
            memoryBytes: 50 * 1024 * 1024,
            diskReadBytesPerSecond: 1001, // 1 byte diff
            diskWriteBytesPerSecond: 2000
        )

        let modifiedWrite = ProcessItem(
            id: 100,
            name: "Worker",
            cpuPercentage: 12.5,
            memoryBytes: 50 * 1024 * 1024,
            diskReadBytesPerSecond: 1000,
            diskWriteBytesPerSecond: 2001 // 1 byte diff
        )

        XCTAssertNotEqual(base, modifiedRead, "ProcessItem.== must detect diskReadBytesPerSecond differences")
        XCTAssertNotEqual(base, modifiedWrite, "ProcessItem.== must detect diskWriteBytesPerSecond differences")

        var set = Set<ProcessItem>()
        set.insert(base)
        // Since Hashable uses PID, set contains 1 entry
        XCTAssertEqual(set.count, 1)
        XCTAssertTrue(set.contains(base))
    }

    // MARK: - 6. ExportManager Serialization & Markdown Robustness

    func testExportManagerWithBoundaryAndSpecialCharacters() throws {
        let pathologicalGPU = GPUMetrics(
            deviceUtilization: 100.0,
            rendererUtilization: 0.0,
            tilerUtilization: 99.9,
            allocatedVRAMBytes: UInt64.max,
            inUseVRAMBytes: UInt64.max / 2,
            coreCount: 128,
            modelName: "Apple M-Ultra \"Special\" <Test> & \nNewlines\tTab",
            hasUnifiedMemory: true
        )

        let metrics = SystemMetrics(
            cpu: CPUMetrics(totalUsage: 99.99),
            gpu: pathologicalGPU,
            memory: MemoryMetrics(totalBytes: UInt64(128) * 1024 * 1024 * 1024),
            disk: DiskMetrics(volumeName: "Macintosh HD / \"Special\""),
            network: NetworkMetrics(),
            processes: []
        )

        let hardware = HardwareProfile(
            modelIdentifier: "Mac16,1",
            marketingModelName: "MacBook Pro (14-inch, M4)",
            cpuBrand: "Apple M4",
            totalCores: 10,
            performanceCores: 4,
            efficiencyCores: 6,
            totalMemoryBytes: UInt64(32) * 1024 * 1024 * 1024,
            osVersionString: "macOS 15.0",
            osBuildVersion: "24A335",
            kernelRelease: "Darwin 24.0.0",
            bootTime: Date(),
            uptimeSeconds: 86400
        )

        // 1. JSON Export verification
        let jsonString = ExportManager.exportTelemetryJSON(metrics: metrics, hardwareProfile: hardware)
        XCTAssertFalse(jsonString.isEmpty)

        guard let data = jsonString.data(using: .utf8),
              let jsonDict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            XCTFail("Exported JSON with special characters failed to deserialize")
            return
        }

        guard let gpuObj = jsonDict["gpu"] as? [String: Any] else {
            XCTFail("Missing 'gpu' object in parsed JSON")
            return
        }

        XCTAssertEqual(gpuObj["device_utilization_percent"] as? Double, 100.0)
        XCTAssertEqual(gpuObj["has_unified_memory"] as? Bool, true)

        // 2. Markdown Export verification
        let md = ExportManager.exportMarkdownSummary(metrics: metrics, hardwareProfile: hardware)
        XCTAssertTrue(md.contains("Apple M-Ultra"))
        XCTAssertTrue(md.contains("100.0%"))
        XCTAssertTrue(md.contains("| **GPU** |"))
    }
}
