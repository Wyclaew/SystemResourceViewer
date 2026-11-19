import XCTest
@testable import SystemResourceViewer

final class Milestone3Challenger2StressTests: XCTestCase {

    // MARK: - 1. Multi-Tab Navigation & Telemetry Continuity Stress Tests

    @MainActor
    func testMultiTabNavigationRapidCycling500Iterations() async {
        let vm = DashboardViewModel(interval: 0.1)
        let tabs = DashboardTab.allCases
        XCTAssertEqual(tabs.count, 4)

        // Verify initial state
        XCTAssertEqual(vm.selectedTab, .processes)
        XCTAssertEqual(vm.cpuHistory.count, 60)
        XCTAssertEqual(vm.cpuHistory15m.count, 900)

        let startTime = Date()

        // Rapidly cycle through all 4 tabs across 500 iterations
        for i in 1...500 {
            let targetTab = tabs[i % tabs.count]
            vm.selectedTab = targetTab

            // Invariant verification on each iteration
            XCTAssertEqual(vm.selectedTab, targetTab, "selectedTab must match target at iteration \(i)")

            // Periodically inspect secondary tab-dependent invariants
            if i % 50 == 0 {
                XCTAssertEqual(vm.cpuHistory.count, 60, "cpuHistory buffer capacity must be preserved")
                XCTAssertEqual(vm.cpuHistory15m.count, 900, "cpuHistory15m buffer capacity must be preserved")
                XCTAssertFalse(vm.hardwareProfile.marketingModelName.isEmpty, "Hardware profile must remain populated")
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        XCTAssertLessThan(elapsed, 3.0, "500 tab transitions must complete smoothly under 3 seconds without stutter")

        // Final sanity check
        vm.selectedTab = .systemProfile
        XCTAssertEqual(vm.selectedTab, .systemProfile)
    }

    @MainActor
    func testMultiTabNavigationUnderConcurrentTelemetryIngestion() async {
        // ViewModel initialized with fast 0.05s polling interval
        let vm = DashboardViewModel(interval: 0.05)
        let tabs = DashboardTab.allCases

        let iterations = 500
        var completedTabTransitions = 0

        for i in 0..<iterations {
            let tab = tabs[i % tabs.count]
            vm.selectedTab = tab
            completedTabTransitions += 1

            // Concurrently yield execution slightly to allow scheduler telemetry stream tasks to interleave
            if i % 100 == 0 {
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }

        XCTAssertEqual(completedTabTransitions, iterations)
        XCTAssertEqual(vm.cpuHistory.count, 60)
        XCTAssertEqual(vm.cpuHistory15m.count, 900)
    }

    @MainActor
    func testDashboardViewModelLifecycleDeallocation() {
        weak var weakVM: DashboardViewModel?
        autoreleasepool {
            let vm = DashboardViewModel(interval: 1.0)
            weakVM = vm
            XCTAssertNotNil(weakVM)

            // Switch tabs
            vm.selectedTab = .diagnostics
            vm.selectedTab = .history
            vm.selectedTab = .systemProfile
            vm.selectedTab = .processes
        }

        // Verify that DashboardViewModel deallocates cleanly without memory leaks or retain cycles
        XCTAssertNil(weakVM, "DashboardViewModel must cleanly deallocate when released")
    }

    // MARK: - 2. History Charts & RingBuffer 10,000 Points Stress Tests

    func testRingBufferMassiveDatasetAndMultiTimelineSlicing() {
        var ringBuffer = RingBuffer<Double>(capacity: 900)
        let totalPoints = 10_000

        // Generate 10,000 deterministic pseudo-random points
        var rawValues: [Double] = []
        rawValues.reserveCapacity(totalPoints)

        for i in 0..<totalPoints {
            // Predictable mathematical function creating peaks, valleys, and fractional floats
            let value = (sin(Double(i) * 0.05) + 1.0) * 45.0 + (Double(i % 10))
            rawValues.append(value)
            ringBuffer.append(value)
        }

        // Invariant: count must be capped at capacity
        XCTAssertEqual(ringBuffer.count, 900)
        XCTAssertEqual(ringBuffer.capacity, 900)

        // Reference array: the last 900 points of rawValues
        let expected900 = Array(rawValues.suffix(900))
        XCTAssertEqual(expected900.count, 900)

        // Verify element-by-element equivalence between ringBuffer and reference array
        for i in 0..<900 {
            XCTAssertEqual(ringBuffer[i], expected900[i], accuracy: 1e-9, "Element at index \(i) mismatch")
        }

        let arrayProjection = ringBuffer.toArray()
        XCTAssertEqual(arrayProjection.count, 900)
        for i in 0..<900 {
            XCTAssertEqual(arrayProjection[i], expected900[i], accuracy: 1e-9)
        }

        // Test Multi-Timeline Slicing
        // 1m Slice: last 60 samples
        let slice1m = Array(ringBuffer.suffix(HistoryTimelineRange.oneMinute.sampleCount))
        let expected1m = Array(expected900.suffix(60))
        XCTAssertEqual(slice1m.count, 60)
        XCTAssertEqual(slice1m, expected1m)

        let stats1m = TimelineStatistics(values: slice1m)
        XCTAssertEqual(stats1m.min, expected1m.min()!, accuracy: 1e-9)
        XCTAssertEqual(stats1m.max, expected1m.max()!, accuracy: 1e-9)
        let mean1m = expected1m.reduce(0.0, +) / Double(expected1m.count)
        XCTAssertEqual(stats1m.mean, mean1m, accuracy: 1e-9)
        XCTAssertEqual(stats1m.current, expected1m.last!, accuracy: 1e-9)

        // 5m Slice: last 300 samples
        let slice5m = Array(ringBuffer.suffix(HistoryTimelineRange.fiveMinutes.sampleCount))
        let expected5m = Array(expected900.suffix(300))
        XCTAssertEqual(slice5m.count, 300)
        XCTAssertEqual(slice5m, expected5m)

        let stats5m = TimelineStatistics(values: slice5m)
        XCTAssertEqual(stats5m.min, expected5m.min()!, accuracy: 1e-9)
        XCTAssertEqual(stats5m.max, expected5m.max()!, accuracy: 1e-9)
        let mean5m = expected5m.reduce(0.0, +) / Double(expected5m.count)
        XCTAssertEqual(stats5m.mean, mean5m, accuracy: 1e-9)
        XCTAssertEqual(stats5m.current, expected5m.last!, accuracy: 1e-9)

        // 15m Slice: last 900 samples
        let slice15m = Array(ringBuffer.suffix(HistoryTimelineRange.fifteenMinutes.sampleCount))
        XCTAssertEqual(slice15m.count, 900)
        XCTAssertEqual(slice15m, expected900)

        let stats15m = TimelineStatistics(values: slice15m)
        XCTAssertEqual(stats15m.min, expected900.min()!, accuracy: 1e-9)
        XCTAssertEqual(stats15m.max, expected900.max()!, accuracy: 1e-9)
        let mean15m = expected900.reduce(0.0, +) / Double(expected900.count)
        XCTAssertEqual(stats15m.mean, mean15m, accuracy: 1e-9)
        XCTAssertEqual(stats15m.current, expected900.last!, accuracy: 1e-9)
    }

    func testTimelineStatisticsEdgeCases() {
        // 1. Empty values
        let emptyStats = TimelineStatistics(values: [])
        XCTAssertEqual(emptyStats.min, 0.0)
        XCTAssertEqual(emptyStats.max, 0.0)
        XCTAssertEqual(emptyStats.mean, 0.0)
        XCTAssertEqual(emptyStats.current, 0.0)

        // 2. Uniform values
        let uniformStats = TimelineStatistics(values: Array(repeating: 77.7, count: 500))
        XCTAssertEqual(uniformStats.min, 77.7, accuracy: 1e-9)
        XCTAssertEqual(uniformStats.max, 77.7, accuracy: 1e-9)
        XCTAssertEqual(uniformStats.mean, 77.7, accuracy: 1e-9)
        XCTAssertEqual(uniformStats.current, 77.7, accuracy: 1e-9)

        // 3. Extreme outliers
        let outlierStats = TimelineStatistics(values: [-1000.0, 0.0, 10000.0])
        XCTAssertEqual(outlierStats.min, -1000.0)
        XCTAssertEqual(outlierStats.max, 10000.0)
        XCTAssertEqual(outlierStats.mean, 3000.0, accuracy: 1e-9)
        XCTAssertEqual(outlierStats.current, 10000.0)
    }

    // MARK: - 3. UserSettings Persistence & Recovery Stress Tests

    func testUserSettingsConcurrentReadsAndWrites() async {
        let suiteName = "com.systemresourceviewer.test.concurrent.\(UUID().uuidString)"
        guard let testDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        // Run 50 concurrent writers with varied configurations using the suiteName
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    guard let defaults = UserDefaults(suiteName: suiteName) else { return }
                    var s = UserSettings()
                    s.refreshInterval = Double(i + 1) * 0.1
                    s.startupTab = (i % 2 == 0) ? "Diagnostics" : "History"
                    s.themeOverride = (i % 3 == 0) ? .dark : .light
                    s.cpuAlertThreshold = Double(70 + (i % 25))
                    s.save(to: defaults)

                    _ = UserSettings.load(from: defaults)
                }
            }
        }

        // Verify that loading after concurrent stress yields valid, uncorrupted UserSettings
        let finalSettings = UserSettings.load(from: testDefaults)
        XCTAssertGreaterThan(finalSettings.refreshInterval, 0.0)
        XCTAssertTrue(["Diagnostics", "History"].contains(finalSettings.startupTab))
        XCTAssertTrue([AppTheme.dark, AppTheme.light].contains(finalSettings.themeOverride))
    }

    func testUserSettingsCorruptedDataRecovery() {
        let suiteName = "com.systemresourceviewer.test.corrupt.\(UUID().uuidString)"
        guard let testDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        let userDefaultsKey = "com.systemresourceviewer.userSettings"

        // Scenario A: Completely empty byte buffer
        testDefaults.set(Data(), forKey: userDefaultsKey)
        let loadedEmpty = UserSettings.load(from: testDefaults)
        XCTAssertEqual(loadedEmpty, UserSettings.defaultSettings, "Must recover to defaultSettings on empty data")

        // Scenario B: Corrupted random non-JSON bytes
        let garbageBytes = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0xFF, 0x42])
        testDefaults.set(garbageBytes, forKey: userDefaultsKey)
        let loadedGarbage = UserSettings.load(from: testDefaults)
        XCTAssertEqual(loadedGarbage, UserSettings.defaultSettings, "Must recover to defaultSettings on corrupted binary garbage")

        // Scenario C: Truncated JSON
        let truncatedJSON = Data("{\"refreshInterval\": 3.0, \"startupTab\": \"Diag".utf8)
        testDefaults.set(truncatedJSON, forKey: userDefaultsKey)
        let loadedTruncated = UserSettings.load(from: testDefaults)
        XCTAssertEqual(loadedTruncated, UserSettings.defaultSettings, "Must recover to defaultSettings on truncated JSON")

        // Scenario D: Incompatible schema (string type where double is expected)
        let incompatibleJSON = Data("{\"refreshInterval\": \"very-fast\", \"startupTab\": 123}".utf8)
        testDefaults.set(incompatibleJSON, forKey: userDefaultsKey)
        let loadedIncompatible = UserSettings.load(from: testDefaults)
        XCTAssertEqual(loadedIncompatible, UserSettings.defaultSettings, "Must recover to defaultSettings on type-incompatible JSON")
    }

    func testUserSettingsEdgeCaseValuesRoundTrip() throws {
        let suiteName = "com.systemresourceviewer.test.edge.\(UUID().uuidString)"
        guard let testDefaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated UserDefaults suite")
            return
        }
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        var settings = UserSettings()
        settings.refreshInterval = 0.0001
        settings.startupTab = "🚀 Custom Tab with Emojis & Spaces ⚡️"
        settings.themeOverride = .system
        settings.historyTimelineRange = "999h"
        settings.cpuAlertThreshold = 0.0
        settings.cpuAlertEnabled = false
        settings.memoryPressureAlertEnabled = false
        settings.thermalAlertThreshold = 1000.0
        settings.thermalAlertEnabled = false
        settings.privacySettings.maskSensitiveArguments = true
        settings.privacySettings.maskLocalIPAddress = true
        settings.privacySettings.hideSystemProcessesByDefault = true

        settings.save(to: testDefaults)

        let loaded = UserSettings.load(from: testDefaults)
        XCTAssertEqual(loaded.refreshInterval, 0.0001)
        XCTAssertEqual(loaded.startupTab, "🚀 Custom Tab with Emojis & Spaces ⚡️")
        XCTAssertEqual(loaded.historyTimelineRange, "999h")
        XCTAssertEqual(loaded.cpuAlertThreshold, 0.0)
        XCTAssertFalse(loaded.cpuAlertEnabled)
        XCTAssertFalse(loaded.memoryPressureAlertEnabled)
        XCTAssertEqual(loaded.thermalAlertThreshold, 1000.0)
        XCTAssertFalse(loaded.thermalAlertEnabled)
        XCTAssertTrue(loaded.privacySettings.maskSensitiveArguments)
        XCTAssertTrue(loaded.privacySettings.maskLocalIPAddress)
        XCTAssertTrue(loaded.privacySettings.hideSystemProcessesByDefault)
    }

    // MARK: - 4. AlertEvaluator Hysteresis & Cooldown Flood Stress Tests

    func testAlertEvaluatorFloodConditions100RapidCrossings() {
        let config = AlertConfiguration(
            cpuThreshold: 90.0,
            cpuAlertsEnabled: true,
            cooldownInterval: 60.0
        )
        let t0 = Date()
        var firedMap: [AlertType: Date] = [:]

        // 1. Initial breach at t0 -> Should trigger exactly 1 alert
        let metricsBreach = SystemMetrics(
            cpu: CPUMetrics(totalUsage: 94.0, userPercentage: 50.0, systemPercentage: 44.0, idlePercentage: 6.0)
        )
        let initialResult = AlertEvaluator.evaluate(
            metrics: metricsBreach,
            config: config,
            lastFired: firedMap,
            now: t0
        )
        XCTAssertEqual(initialResult.newAlerts.count, 1)
        XCTAssertEqual(initialResult.newAlerts.first?.type, .cpuHigh)
        firedMap = initialResult.updatedFired

        // 2. Flood with 100 rapid oscillations (threshold crossings) within the 60s cooldown window
        var suppressedCount = 0
        for i in 1...100 {
            // Timestamp advances by fractions of a second up to 59.9s
            let stepTime = t0.addingTimeInterval(Double(i) * 0.59) // 0.59s to 59.0s
            // Flapping metric: alternating between 98% (severe breach) and 40% (normal)
            let usage = (i % 2 == 0) ? 98.0 : 40.0
            let metricsFlap = SystemMetrics(
                cpu: CPUMetrics(totalUsage: usage, userPercentage: usage / 2, systemPercentage: usage / 2, idlePercentage: 100 - usage)
            )

            let result = AlertEvaluator.evaluate(
                metrics: metricsFlap,
                config: config,
                lastFired: firedMap,
                now: stepTime
            )

            if result.newAlerts.isEmpty {
                suppressedCount += 1
            } else {
                XCTFail("Duplicate alert spam detected at tick \(i) (\(stepTime.timeIntervalSince(t0))s after t0)")
            }
            firedMap = result.updatedFired
        }

        XCTAssertEqual(suppressedCount, 100, "All 100 rapid threshold crossings within 60s cooldown must be suppressed")

        // 3. Post-cooldown re-trigger at t0 + 60.01 seconds -> Must trigger exactly 1 new alert
        let tCooldownExpired = t0.addingTimeInterval(60.01)
        let expiredResult = AlertEvaluator.evaluate(
            metrics: metricsBreach,
            config: config,
            lastFired: firedMap,
            now: tCooldownExpired
        )
        XCTAssertEqual(expiredResult.newAlerts.count, 1, "Alert must re-trigger after cooldown interval has elapsed")
        XCTAssertEqual(expiredResult.newAlerts.first?.type, .cpuHigh)
    }

    func testAlertEvaluatorMultiMetricConcurrentFlood() {
        let config = AlertConfiguration(
            cpuThreshold: 90.0,
            cpuAlertsEnabled: true,
            memoryUsageThreshold: 90.0,
            memoryPressureAlertsEnabled: true,
            thermalThreshold: 90.0,
            thermalAlertsEnabled: true,
            diskThreshold: 95.0,
            diskAlertsEnabled: true,
            cooldownInterval: 60.0
        )

        let t0 = Date()
        var firedMap: [AlertType: Date] = [:]

        // Massive system-wide saturation
        let criticalMetrics = SystemMetrics(
            cpu: CPUMetrics(totalUsage: 99.0, userPercentage: 50.0, systemPercentage: 49.0, idlePercentage: 1.0),
            memory: MemoryMetrics(
                totalBytes: 16 * 1024 * 1024 * 1024,
                appMemoryBytes: 15 * 1024 * 1024 * 1024,
                pressureLevel: .critical
            ),
            disk: DiskMetrics(volumeName: "Macintosh HD", totalBytes: 1000, freeBytes: 10, readBytesPerSecond: 0, writeBytesPerSecond: 0),
            thermal: ThermalMetrics(socDieTemperature: 98.0, thermalState: .critical)
        )

        // Tick 0: All 4 alert types trigger simultaneously
        let initialResult = AlertEvaluator.evaluate(
            metrics: criticalMetrics,
            config: config,
            lastFired: firedMap,
            now: t0
        )
        XCTAssertEqual(initialResult.newAlerts.count, 4)
        firedMap = initialResult.updatedFired

        // 50 subsequent floods within 30 seconds
        for i in 1...50 {
            let floodTime = t0.addingTimeInterval(Double(i) * 0.5)
            let floodResult = AlertEvaluator.evaluate(
                metrics: criticalMetrics,
                config: config,
                lastFired: firedMap,
                now: floodTime
            )
            XCTAssertTrue(floodResult.newAlerts.isEmpty, "All subsystem alerts must be suppressed during cooldown")
            firedMap = floodResult.updatedFired
        }

        // After 61 seconds: all 4 can fire again
        let tAfter = t0.addingTimeInterval(61.0)
        let afterResult = AlertEvaluator.evaluate(
            metrics: criticalMetrics,
            config: config,
            lastFired: firedMap,
            now: tAfter
        )
        XCTAssertEqual(afterResult.newAlerts.count, 4, "All 4 alerts should be eligible to fire after 60s cooldown")
    }

    func testAlertEvaluatorBackwardsClockResilience() {
        let config = AlertConfiguration(cpuThreshold: 90.0, cpuAlertsEnabled: true, cooldownInterval: 60.0)
        let t0 = Date()
        let breach = SystemMetrics(cpu: CPUMetrics(totalUsage: 95.0, userPercentage: 50.0, systemPercentage: 45.0, idlePercentage: 5.0))

        let r0 = AlertEvaluator.evaluate(metrics: breach, config: config, lastFired: [:], now: t0)
        XCTAssertEqual(r0.newAlerts.count, 1)

        // Simulated NTP clock rollback (now is in the past compared to lastFired)
        let tPast = t0.addingTimeInterval(-100.0)
        let rPast = AlertEvaluator.evaluate(metrics: breach, config: config, lastFired: r0.updatedFired, now: tPast)
        XCTAssertTrue(rPast.newAlerts.isEmpty, "Backwards clock time must not trigger false alerts")
    }

    // MARK: - 5. ExportManager RFC 4180 Escaping & Privacy Masking Stress Tests

    func testExportManagerRFC4180HostileStringsEscaping() {
        let hostileProcessNames = [
            "NormalProcess",
            "Process, With, Commas",
            "Process \"DoubleQuotes\" Embedded",
            "Process \"\"TwoDoubleQuotes\"\"",
            "Process 'Single' and \"Double\"",
            "Process\nWith\nNewlines",
            "Process\r\nWith\r\nCRLF",
            "Process, \"Mixed, Commas, And, Quotes\"",
            "🔥 Rocket, \"Cat 🐱\", And \"Quotes\" 💻",
            "Process with ; semicolons & ampersands",
            "Process with \\ backslashes / slashes",
            "\"Leading quote and trailing quote\"",
            "Unclosed \" single quote in middle",
            "   Whitespace and \t tabs   "
        ]

        var mockProcesses: [ProcessItem] = []
        for (idx, name) in hostileProcessNames.enumerated() {
            let p = ProcessItem(
                id: pid_t(1000 + idx),
                name: name,
                cpuPercentage: Double(idx) * 2.5,
                memoryBytes: UInt64(idx * 10_000_000),
                architecture: "arm64, \"apple\"",
                ownerUser: "user, \"\(idx)\"",
                executablePath: "/usr/local/bin/\(name)",
                isSuspended: (idx % 2 == 0)
            )
            mockProcesses.append(p)
        }

        let csv = ExportManager.exportProcessCSV(processes: mockProcesses)

        // Verify CSV format with our RFC 4180 parser
        let parsedRows = parseRFC4180CSV(csv)

        // Row 0 is header, followed by rows for each process
        XCTAssertEqual(parsedRows.count, hostileProcessNames.count + 1)

        // Verify header columns
        let expectedHeader = ["PID","PPID","Name","User","Architecture","Category","Status","CPU(%)","Memory(MB)","DiskRead(KB/s)","DiskWrite(KB/s)","Threads","Path"]
        XCTAssertEqual(parsedRows[0], expectedHeader)

        // Verify each row parsed back exactly matches the original input name
        for (idx, originalName) in hostileProcessNames.enumerated() {
            guard idx + 1 < parsedRows.count else {
                XCTFail("Missing row for process \(idx)")
                continue
            }
            let row = parsedRows[idx + 1]
            XCTAssertEqual(row.count, 13, "Row \(idx + 1) must have exactly 13 columns")
            guard row.count >= 5 else {
                XCTFail("Row \(idx + 1) has only \(row.count) columns (expected 13): \(row)")
                continue
            }

            let parsedPid = row[0]
            let parsedName = row[2]
            let parsedUser = row[3]
            let parsedArch = row[4]

            XCTAssertEqual(parsedPid, "\(1000 + idx)")
            XCTAssertEqual(parsedName, originalName, "Process name must be parsed back identically per RFC 4180")
            XCTAssertEqual(parsedUser, "user, \"\(idx)\"")
            XCTAssertEqual(parsedArch, "arm64, \"apple\"")
        }
    }

    func testSensitiveDataSanitizerExhaustiveTokenAndCredentialScrubbing() {
        let privacy = PrivacySettings(maskSensitiveArguments: true, allowExternalSocketProbe: true, maskLocalIPAddress: true)

        // 1. OpenAI / Anthropic AI API tokens
        let aiToken = "sk-ant-api03-abcdef1234567890abcdef1234567890"
        let scrubbedAI = privacy.sanitize(argument: "export OPENAI_API_KEY=\(aiToken)")
        XCTAssertFalse(scrubbedAI.contains(aiToken))
        XCTAssertTrue(scrubbedAI.contains("***REDACTED***"))

        // 2. Project scoped token
        let projToken = "sk-proj-1234567890abcdef1234567890_zyxwvutsrq"
        let scrubbedProj = privacy.sanitize(argument: "--key=\(projToken)")
        XCTAssertFalse(scrubbedProj.contains(projToken))
        XCTAssertTrue(scrubbedProj.contains("***REDACTED***"))

        // 3. GitHub Personal Access Tokens (ghp_, ghs_, ghu_)
        let ghpToken = "ghp_1234567890abcdefghijklmnopqrstuvwxyz"
        let scrubbedGHP = privacy.sanitize(argument: "git clone https://\(ghpToken)@github.com/org/repo")
        XCTAssertFalse(scrubbedGHP.contains(ghpToken))
        XCTAssertTrue(scrubbedGHP.contains("***REDACTED***"))

        // 4. AWS Access Key ID
        let awsKey = "AKIAIOSFODNN7EXAMPLE"
        let scrubbedAWS = privacy.sanitize(argument: "AWS_ACCESS_KEY_ID=\(awsKey)")
        XCTAssertFalse(scrubbedAWS.contains(awsKey))
        XCTAssertTrue(scrubbedAWS.contains("***REDACTED***"))

        // 5. AWS Secret Access Key
        let awsSecret = "aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        let scrubbedSecret = privacy.sanitize(argument: awsSecret)
        XCTAssertFalse(scrubbedSecret.contains("wJalrXUtnFEMI"))
        XCTAssertTrue(scrubbedSecret.contains("***REDACTED***"))

        // 6. Bearer token
        let bearerToken = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.xyz"
        let scrubbedBearer = privacy.sanitize(argument: "Authorization: \(bearerToken)")
        XCTAssertFalse(scrubbedBearer.contains("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"))
        XCTAssertTrue(scrubbedBearer.contains("***REDACTED***"))

        // 7. CLI flag arguments (--password=, -p, etc.)
        let cliPassword = "--password=MySuperSecretPassword123"
        let scrubbedCLI = privacy.sanitize(argument: cliPassword)
        XCTAssertFalse(scrubbedCLI.contains("MySuperSecretPassword123"))
        XCTAssertTrue(scrubbedCLI.contains("--password=***REDACTED***"))

        // 8. Multi-token CLI flag array
        let multiTokenArgs = ["my_service", "--password", "SecretP@ssw0rd!", "--port", "8080"]
        let scrubbedMulti = privacy.sanitize(arguments: multiTokenArgs)
        XCTAssertEqual(scrubbedMulti, ["my_service", "--password", "***REDACTED***", "--port", "8080"])

        // 9. Database URI embedded credentials
        let dbURI = "postgres://root:p@ssw0rd123@db.prod.internal:5432/main"
        let scrubbedURI = privacy.sanitize(argument: dbURI)
        XCTAssertFalse(scrubbedURI.contains("p@ssw0rd123"))
        XCTAssertTrue(scrubbedURI.contains("postgres://root:***REDACTED***@db.prod.internal:5432/main"))
    }

    func testExportManagerIPv4MaskingAndBypassFreedom() {
        let privacyMasked = PrivacySettings(maskSensitiveArguments: true, allowExternalSocketProbe: true, maskLocalIPAddress: true)
        let privacyUnmasked = PrivacySettings(maskSensitiveArguments: true, allowExternalSocketProbe: true, maskLocalIPAddress: false)

        // Test sanitize(ipv4:)
        XCTAssertEqual(privacyMasked.sanitize(ipv4: "192.168.1.100"), "192.168.*.*")
        XCTAssertEqual(privacyMasked.sanitize(ipv4: "10.0.0.1"), "10.0.*.*")
        XCTAssertEqual(privacyMasked.sanitize(ipv4: "172.16.254.1"), "172.16.*.*")
        XCTAssertEqual(privacyMasked.sanitize(ipv4: "127.0.0.1"), "127.0.*.*")
        XCTAssertEqual(privacyMasked.sanitize(ipv4: "unknown"), "•••.•••.•••.•••")
        XCTAssertEqual(privacyMasked.sanitize(ipv4: ""), "•••.•••.•••.•••")

        XCTAssertEqual(privacyUnmasked.sanitize(ipv4: "192.168.1.100"), "192.168.1.100")

        // Test in ExportManager.exportTelemetryJSON
        let metrics = SystemMetrics(network: NetworkMetrics(primaryInterfaceName: "en0", localIPv4: "192.168.1.200"))
        let hardware = HardwareProfile(modelIdentifier: "Mac14,6", marketingModelName: "MacBook Pro", cpuBrand: "Apple M2 Max", totalCores: 12, performanceCores: 8, efficiencyCores: 4, totalMemoryBytes: 32000000000, osVersionString: "macOS 14", osBuildVersion: "23A", kernelRelease: "Darwin 23", bootTime: Date(), uptimeSeconds: 1000)

        let jsonMasked = ExportManager.exportTelemetryJSON(metrics: metrics, hardwareProfile: hardware, privacySettings: privacyMasked)
        XCTAssertFalse(jsonMasked.contains("192.168.1.200"), "Raw IP address must not appear in JSON telemetry when masking is active")
        XCTAssertTrue(jsonMasked.contains("192.168.*.*"), "Masked IP address must be present in JSON telemetry")

        // Test in ExportManager.exportMarkdownSummary
        let mdMasked = ExportManager.exportMarkdownSummary(metrics: metrics, hardwareProfile: hardware, privacySettings: privacyMasked)
        XCTAssertFalse(mdMasked.contains("192.168.1.200"), "Raw IP address must not appear in Markdown summary when masking is active")
        XCTAssertTrue(mdMasked.contains("192.168.*.*"), "Masked IP address must be present in Markdown summary")
    }

    // MARK: - Helper: RFC 4180 CSV Compliant Parser

    private func parseRFC4180CSV(_ csv: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false

        let scalars = Array(csv.unicodeScalars)
        var i = 0

        while i < scalars.count {
            let s = scalars[i]

            if insideQuotes {
                if s == "\"" {
                    // Escaped double quote ("")
                    if i + 1 < scalars.count && scalars[i + 1] == "\"" {
                        currentField.append("\"")
                        i += 2
                        continue
                    } else {
                        // Closing quote
                        insideQuotes = false
                        i += 1
                        continue
                    }
                } else {
                    currentField.append(Character(s))
                    i += 1
                    continue
                }
            } else {
                if s == "\"" {
                    insideQuotes = true
                    i += 1
                    continue
                } else if s == "," {
                    currentRow.append(currentField)
                    currentField = ""
                    i += 1
                    continue
                } else if s == "\r" {
                    if i + 1 < scalars.count && scalars[i + 1] == "\n" {
                        i += 1
                    }
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow = []
                    currentField = ""
                    i += 1
                    continue
                } else if s == "\n" {
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow = []
                    currentField = ""
                    i += 1
                    continue
                } else {
                    currentField.append(Character(s))
                    i += 1
                    continue
                }
            }
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        return rows
    }
}
