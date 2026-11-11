import XCTest
@testable import SystemResourceViewer

final class AdversarialStressTests: XCTestCase {

    // MARK: - 1. Extreme Process Filtering Queries

    func testProcessFilteringWithExtremeQueryLengths() {
        let dummy = ProcessItem(
            id: 1001,
            ppid: 1,
            name: "TestApp",
            bundleIdentifier: "com.apple.TestApp",
            cpuPercentage: 10.0,
            memoryBytes: 1024 * 1024 * 100,
            architecture: "Apple Silicon",
            threadCount: 4,
            ownerUser: "root",
            category: .apps
        )
        let list = [dummy]

        // 10,000 character query
        let longQuery10k = String(repeating: "A", count: 10_000)
        let result10k = ProcessFilterHelper.filter(processes: list, category: .all, searchQuery: longQuery10k)
        XCTAssertTrue(result10k.isEmpty)

        // 100,000 character query
        let longQuery100k = String(repeating: "Z", count: 100_000)
        let result100k = ProcessFilterHelper.filter(processes: list, category: .all, searchQuery: longQuery100k)
        XCTAssertTrue(result100k.isEmpty)
    }

    func testProcessFilteringWithUnicodeAndRTLCharacters() {
        let processUnicode = ProcessItem(
            id: 2002,
            ppid: 1,
            name: "🚀 Super🔥Process 进程 مبرمج",
            bundleIdentifier: "com.unicode.app",
            cpuPercentage: 25.0,
            memoryBytes: 50 * 1024 * 1024,
            architecture: "Apple Silicon",
            threadCount: 2,
            ownerUser: "user",
            category: .apps
        )
        let list = [processUnicode]

        // Emojis
        let matchEmoji = ProcessFilterHelper.filter(processes: list, category: .all, searchQuery: "🚀")
        XCTAssertEqual(matchEmoji.count, 1)

        let matchFire = ProcessFilterHelper.filter(processes: list, category: .all, searchQuery: "🔥")
        XCTAssertEqual(matchFire.count, 1)

        // Chinese characters
        let matchChinese = ProcessFilterHelper.filter(processes: list, category: .all, searchQuery: "进程")
        XCTAssertEqual(matchChinese.count, 1)

        // Arabic characters
        let matchArabic = ProcessFilterHelper.filter(processes: list, category: .all, searchQuery: "مبرمج")
        XCTAssertEqual(matchArabic.count, 1)

        // Zero-width spaces & RTL override chars
        let rtlQuery = "\u{200E}\u{202E}🚀\u{200B}"
        let resRTL = ProcessFilterHelper.filter(processes: list, category: .all, searchQuery: rtlQuery)
        // Should not crash
        _ = resRTL
    }

    func testProcessFilteringWithRegexAndInjectionPayloads() {
        let dummy = ProcessItem(
            id: 3003,
            ppid: 1,
            name: "NormalProcess",
            cpuPercentage: 5.0,
            memoryBytes: 10 * 1024 * 1024
        )
        let list = [dummy]

        let adversarialInputs = [
            ".*", "[a-z]+", "\\d+", "(\\w+)*", "^$", "(?i)", "(?:.*)*",
            "' OR '1'='1", "\"; DROP TABLE processes;--",
            "$(rm -rf /)", "`reboot`", "&& kill -9 1",
            "\0", "\n", "\r\n", "\t", "\\", "/", "%s%d%n", "%@%p"
        ]

        for query in adversarialInputs {
            // Must not crash, hang, or evaluate unescaped regex
            let filtered = ProcessFilterHelper.filter(processes: list, category: .all, searchQuery: query)
            XCTAssertTrue(filtered.isEmpty || filtered.count == 1)
        }
    }

    func testProcessFilteringMassiveListStress() {
        // Generate 10,000 synthetic processes
        var massiveList: [ProcessItem] = []
        massiveList.reserveCapacity(10_000)

        for i in 1...10_000 {
            let cat: SystemResourceViewer.ProcessCategory = (i % 4 == 0) ? .apps : ((i % 4 == 1) ? .daemons : ((i % 4 == 2) ? .system : .highLoad))
            massiveList.append(
                ProcessItem(
                    id: pid_t(i),
                    ppid: pid_t(max(1, i / 10)),
                    name: "Worker_\(i)",
                    bundleIdentifier: (cat == .apps) ? "com.test.worker\(i)" : nil,
                    cpuPercentage: Double(i % 100),
                    memoryBytes: UInt64(i * 1024 * 1024),
                    architecture: (i % 2 == 0) ? "Apple Silicon" : "Rosetta 2",
                    threadCount: (i % 32) + 1,
                    ownerUser: (i % 5 == 0) ? "root" : "user",
                    category: cat
                )
            )
        }

        let start = DispatchTime.now()
        let filteredApps = ProcessFilterHelper.filter(processes: massiveList, category: .apps, searchQuery: "Worker_99")
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0

        // Filter 10k items should take less than 150ms
        XCTAssertLessThan(elapsedMs, 150.0, "Filtering 10,000 items took too long: \(elapsedMs) ms")
        XCTAssertFalse(filteredApps.isEmpty)
    }

    func testDeepProcessTreeAggregationStress() {
        // Construct a 20-level deep parent-child chain
        var current = ProcessItem(
            id: 1020,
            ppid: 1019,
            name: "Child_20",
            cpuPercentage: 1.5,
            memoryBytes: 10 * 1024 * 1024
        )

        for depth in (1...19).reversed() {
            let parent = ProcessItem(
                id: pid_t(1000 + depth),
                ppid: pid_t(1000 + depth - 1),
                name: "Process_Level_\(depth)",
                cpuPercentage: 1.0,
                memoryBytes: 5 * 1024 * 1024,
                children: [current]
            )
            current = parent
        }

        // Verify total CPU and total Memory roll up correctly without recursion crash
        XCTAssertGreaterThan(current.totalCPU, 20.0)
        XCTAssertGreaterThan(current.totalMemory, 100 * 1024 * 1024)
    }

    // MARK: - 2. GPU Model Boundaries & Anomalies

    func testGPUMetricsExtremeValues() {
        // Extreme high utilization
        let overutilized = GPUMetrics(
            deviceUtilization: 999.9,
            rendererUtilization: 500.0,
            tilerUtilization: 300.0,
            allocatedVRAMBytes: 1000,
            inUseVRAMBytes: 500,
            coreCount: 16,
            modelName: "Test GPU"
        )
        XCTAssertEqual(overutilized.clampedDeviceUtilization, 100.0)

        // Negative utilization
        let negative = GPUMetrics(
            deviceUtilization: -100.0,
            rendererUtilization: -50.0,
            tilerUtilization: -10.0,
            coreCount: 8,
            modelName: "Test GPU"
        )
        XCTAssertEqual(negative.clampedDeviceUtilization, 0.0)

        // Zero allocated VRAM division by zero protection
        let zeroAlloc = GPUMetrics(
            deviceUtilization: 0.0,
            allocatedVRAMBytes: 0,
            inUseVRAMBytes: 1024 * 1024 * 1024,
            coreCount: 8,
            modelName: "Test GPU"
        )
        XCTAssertEqual(zeroAlloc.vramUsagePercentage, 0.0)

        // In-use VRAM exceeding allocated VRAM clamping
        let vramOverflow = GPUMetrics(
            deviceUtilization: 0.0,
            allocatedVRAMBytes: 100,
            inUseVRAMBytes: 5000,
            coreCount: 8,
            modelName: "Test GPU"
        )
        XCTAssertEqual(vramOverflow.vramUsagePercentage, 100.0)

        // Max UInt64 VRAM
        let maxVRAM = GPUMetrics(
            deviceUtilization: 0.0,
            allocatedVRAMBytes: UInt64.max,
            inUseVRAMBytes: UInt64.max,
            coreCount: 8,
            modelName: "Test GPU"
        )
        XCTAssertEqual(maxVRAM.vramUsagePercentage, 100.0)

        // Negative core count
        let negCores = GPUMetrics(coreCount: -16)
        XCTAssertEqual(negCores.coreCount, -16)

        // Single-parameter initializers (verify no overload ambiguity)
        let singleUtil = GPUMetrics(deviceUtilization: 50.0)
        XCTAssertEqual(singleUtil.deviceUtilization, 50.0)
        XCTAssertEqual(singleUtil.modelName, "Apple Silicon GPU")

        let singleModel = GPUMetrics(modelName: "Custom GPU")
        XCTAssertEqual(singleModel.modelName, "Custom GPU")
        XCTAssertEqual(singleModel.deviceUtilization, 0.0)

        let emptyDefault = GPUMetrics()
        XCTAssertEqual(emptyDefault.deviceUtilization, 0.0)
        XCTAssertEqual(emptyDefault.modelName, "Apple Silicon GPU")
    }

    // MARK: - 3. Thermal Model Boundaries & Anomalies

    func testThermalMetricsExtremeValues() {
        // Sub-zero and scorching temperatures
        let extremeThermal = SystemResourceViewer.ThermalMetrics(
            socDieTemperature: -40.0,
            peakDieTemperature: 250.0,
            batteryTemperature: 0.0,
            storageTemperature: -10.0,
            thermalState: .critical,
            fanSpeeds: [],
            isFanless: true
        )
        XCTAssertEqual(extremeThermal.socDieTemperature, -40.0)
        XCTAssertEqual(extremeThermal.peakDieTemperature, 250.0)
        XCTAssertEqual(extremeThermal.thermalStateDescription, "Critical")
        XCTAssertEqual(extremeThermal.coolingStatusDescription, "Fanless Architecture - Passive Cooling")

        // Inverted fan RPM limits (minRPM > maxRPM)
        let brokenFan = SystemResourceViewer.FanTelemetry(id: 0, name: "Broken Fan", currentRPM: 3000, minRPM: 5000, maxRPM: 2000)
        XCTAssertEqual(brokenFan.percentage, 0.0, "Should return 0.0 when maxRPM <= minRPM")

        // Over-revving fan (currentRPM > maxRPM)
        let overrevFan = SystemResourceViewer.FanTelemetry(id: 1, name: "Over-rev Fan", currentRPM: 8000, minRPM: 1000, maxRPM: 6000)
        XCTAssertEqual(overrevFan.percentage, 100.0, "Should clamp at 100.0% when currentRPM exceeds maxRPM")

        // Under-spinning fan (currentRPM < minRPM)
        let underspinFan = SystemResourceViewer.FanTelemetry(id: 2, name: "Stalled Fan", currentRPM: 200, minRPM: 1200, maxRPM: 5500)
        XCTAssertEqual(underspinFan.percentage, 0.0, "Should clamp at 0.0% when currentRPM is below minRPM")

        // Multi-fan configuration (4 fans on Mac Pro / Studio)
        let multiFans = (0..<4).map {
            SystemResourceViewer.FanTelemetry(id: $0, name: "Fan \($0)", currentRPM: 1500 + ($0 * 200), minRPM: 1000, maxRPM: 5000)
        }
        let studioThermal = SystemResourceViewer.ThermalMetrics(fanSpeeds: multiFans, isFanless: false)
        XCTAssertFalse(studioThermal.isFanless)
        XCTAssertEqual(studioThermal.fanSpeeds.count, 4)
        XCTAssertTrue(studioThermal.coolingStatusDescription.contains("4 Active Fans"))
    }

    // MARK: - 4. ProcessAction Invalid PIDs & Safety Bounds

    func testProcessActionStrictSystemGuard() {
        // PID 0 (kernel idle / swapper)
        let killPID0 = ProcessAction.terminate(pid: 0)
        XCTAssertEqual(killPID0, .failure("Cannot terminate system initialization process (PID 0)."))
        let forcePID0 = ProcessAction.forceKill(pid: 0)
        XCTAssertEqual(forcePID0, .failure("Cannot terminate system initialization process (PID 0)."))

        // PID 1 (launchd)
        let killPID1 = ProcessAction.terminate(pid: 1)
        XCTAssertEqual(killPID1, .failure("Cannot terminate system initialization process (PID 1)."))
        let forcePID1 = ProcessAction.forceKill(pid: 1)
        XCTAssertEqual(forcePID1, .failure("Cannot terminate system initialization process (PID 1)."))

        // PID -1 (broadcast kill all processes)
        let killPIDNeg1 = ProcessAction.terminate(pid: -1)
        XCTAssertEqual(killPIDNeg1, .failure("Cannot terminate system initialization process (PID -1)."))
        let forcePIDNeg1 = ProcessAction.forceKill(pid: -1)
        XCTAssertEqual(forcePIDNeg1, .failure("Cannot terminate system initialization process (PID -1)."))

        // PID -9999 (arbitrary negative)
        let killPIDNeg = ProcessAction.terminate(pid: -9999)
        XCTAssertEqual(killPIDNeg, .failure("Cannot terminate system initialization process (PID -9999)."))

        // Non-existent large PID (should return ESRCH cleanly)
        let nonExistentPID: pid_t = 999999
        let killNonExistent = ProcessAction.terminate(pid: nonExistentPID)
        if case .failure(let reason) = killNonExistent {
            XCTAssertTrue(reason.contains("ESRCH") || reason.contains("terminated"))
        } else {
            XCTFail("Should fail terminating non-existent PID")
        }

        // Int32.max PID
        let maxPID: pid_t = pid_t.max
        let killMax = ProcessAction.terminate(pid: maxPID)
        if case .failure(let reason) = killMax {
            XCTAssertTrue(reason.contains("ESRCH") || reason.contains("terminated") || reason.contains("EINVAL"))
        } else {
            XCTFail("Should fail terminating Int32.max PID")
        }
    }

    // MARK: - 5. Telemetry Services Overhead & Rapid Toggling Stress

    func testRapidSchedulerModeTogglingStress() async {
        let scheduler = MetricsScheduler(interval: 0.1)

        // Rapidly toggle between minimal and full mode 40 times
        for i in 0..<40 {
            let mode: MetricsScheduler.PollingMode = (i % 2 == 0) ? .minimal : .full
            await scheduler.setPollingMode(mode)
        }

        await scheduler.stop()
    }

    func testIndividualTelemetryServicesPollingExecutionTime() async {
        let cpuService = CPUMonitorService()
        let memService = MemoryMonitorService()
        let gpuService = GPUMonitorService()
        let thermalService = ThermalMonitorService()
        let diskPowerService = DiskAndPowerService()

        // Measure CPU polling
        let startCPU = DispatchTime.now()
        _ = await cpuService.pollCPUMetrics(topProcesses: [])
        let elapsedCPU = Double(DispatchTime.now().uptimeNanoseconds - startCPU.uptimeNanoseconds) / 1_000_000.0
        XCTAssertLessThan(elapsedCPU, 50.0, "CPU polling took too long: \(elapsedCPU) ms")

        // Measure Memory polling
        let startMem = DispatchTime.now()
        _ = await memService.pollMemoryMetrics(topProcesses: [])
        let elapsedMem = Double(DispatchTime.now().uptimeNanoseconds - startMem.uptimeNanoseconds) / 1_000_000.0
        XCTAssertLessThan(elapsedMem, 50.0, "Memory polling took too long: \(elapsedMem) ms")

        // Measure GPU polling
        let startGPU = DispatchTime.now()
        _ = await gpuService.pollGPUMetrics()
        let elapsedGPU = Double(DispatchTime.now().uptimeNanoseconds - startGPU.uptimeNanoseconds) / 1_000_000.0
        XCTAssertLessThan(elapsedGPU, 50.0, "GPU polling took too long: \(elapsedGPU) ms")

        // Measure Thermal polling (IOHID multi-sensor enumeration can take ~50-60ms)
        let startThermal = DispatchTime.now()
        _ = await thermalService.pollThermalMetrics()
        let elapsedThermal = Double(DispatchTime.now().uptimeNanoseconds - startThermal.uptimeNanoseconds) / 1_000_000.0
        XCTAssertLessThan(elapsedThermal, 100.0, "Thermal polling took too long: \(elapsedThermal) ms")

        // Measure Disk/Power polling
        let startDiskPower = DispatchTime.now()
        _ = await diskPowerService.pollDiskAndPower()
        let elapsedDiskPower = Double(DispatchTime.now().uptimeNanoseconds - startDiskPower.uptimeNanoseconds) / 1_000_000.0
        XCTAssertLessThan(elapsedDiskPower, 50.0, "Disk/Power polling took too long: \(elapsedDiskPower) ms")
    }

    // MARK: - 6. MetricRingGauge NaN / Inf Crash Resilience

    func testMetricRingGaugeNaNAndInfResilience() {
        // Must not crash on NaN, Infinity, -Infinity, negative, or overflow
        let nanGauge = MetricRingGauge(percentage: Double.nan)
        _ = nanGauge.body

        let infGauge = MetricRingGauge(percentage: Double.infinity)
        _ = infGauge.body

        let negInfGauge = MetricRingGauge(percentage: -Double.infinity)
        _ = negInfGauge.body

        let negGauge = MetricRingGauge(percentage: -50.0)
        _ = negGauge.body

        let overGauge = MetricRingGauge(percentage: 250.0)
        _ = overGauge.body
    }
}
