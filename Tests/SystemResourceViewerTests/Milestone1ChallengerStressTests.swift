import XCTest
@testable import SystemResourceViewer

final class Milestone1ChallengerStressTests: XCTestCase {

    // MARK: - 1. MetricsScheduler Mode Toggling Stress Tests

    func testRapidModeTogglingConcurrency() async {
        let scheduler = MetricsScheduler(interval: 0.1)
        
        // Spawn 20 concurrent tasks, each toggling mode 50 times (1000 toggles total)
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    for j in 0..<50 {
                        let mode: MetricsScheduler.PollingMode = ((i + j) % 2 == 0) ? .full : .minimal
                        await scheduler.setPollingMode(mode)
                    }
                }
            }
        }
        
        // Set mode to .full and stop
        await scheduler.setPollingMode(.full)
        await scheduler.stop()
    }

    func testMetricsSchedulerStreamModeSwitchingPayloads() async {
        let scheduler = MetricsScheduler(interval: 0.2)
        let stream = await scheduler.metricsStream()

        var iterator = stream.makeAsyncIterator()

        // 1. Initial mode is .full
        await scheduler.setPollingMode(.full)
        
        // Read first full snapshot
        guard let fullSnapshot1 = await iterator.next() else {
            XCTFail("Stream should yield a full snapshot")
            return
        }
        XCTAssertFalse(fullSnapshot1.processes.isEmpty, "Full mode should yield processes")

        // 2. Toggle to .minimal
        await scheduler.setPollingMode(.minimal)

        // Read minimal snapshot
        guard let minimalSnapshot = await iterator.next() else {
            XCTFail("Stream should yield a minimal snapshot")
            return
        }
        XCTAssertTrue(minimalSnapshot.processes.isEmpty, "Minimal mode must NOT sample processes (must be empty)")
        XCTAssertTrue(minimalSnapshot.cpu.topProcesses.isEmpty, "Minimal mode must NOT populate top CPU processes")
        XCTAssertTrue(minimalSnapshot.memory.topProcesses.isEmpty, "Minimal mode must NOT populate top Memory processes")
        // Minimal mode should carry forward last known thermal metrics
        XCTAssertEqual(minimalSnapshot.thermal.socDieTemperature, fullSnapshot1.thermal.socDieTemperature)

        // 3. Toggle back to .full
        await scheduler.setPollingMode(.full)

        guard let fullSnapshot2 = await iterator.next() else {
            XCTFail("Stream should yield a full snapshot after switching back")
            return
        }
        XCTAssertFalse(fullSnapshot2.processes.isEmpty, "Full mode must resume yielding processes")

        await scheduler.stop()
    }

    func testModeTogglingUnderConcurrentIntervalChanges() async {
        let scheduler = MetricsScheduler(interval: 0.5)
        
        await withTaskGroup(of: Void.self) { group in
            // Task toggling modes
            group.addTask {
                for i in 0..<30 {
                    let mode: MetricsScheduler.PollingMode = (i % 2 == 0) ? .full : .minimal
                    await scheduler.setPollingMode(mode)
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
            }
            // Task changing intervals
            group.addTask {
                let intervals: [TimeInterval] = [0.1, 0.2, 0.5, 1.0]
                for i in 0..<30 {
                    let interval = intervals[i % intervals.count]
                    await scheduler.setRefreshInterval(interval)
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
            }
        }
        
        await scheduler.stop()
    }

    // MARK: - 2. Background Process Filtering & Sorting Stress Tests

    @MainActor
    func testRapidInputChangesOnDashboardViewModel() async {
        let vm = DashboardViewModel(interval: 5.0)

        // Simulate rapid typing and category switching
        let searchQueries = ["x", "xc", "xco", "xcod", "xcode", "", "s", "sa", "saf", "safari", "kernel", "launchd"]
        let categories: [ProcessCategory] = [.all, .apps, .daemons, .system, .highLoad]
        let sortFields: [ProcessSortField] = [.cpu, .memory, .name, .pid]

        for i in 0..<50 {
            vm.searchText = searchQueries[i % searchQueries.count]
            vm.selectedCategory = categories[i % categories.count]
            vm.sortField = sortFields[i % sortFields.count]
            vm.sortAscending = (i % 2 == 0)
        }

        // Wait briefly for the latest detached task to settle
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Verify state is valid
        XCTAssertNotNil(vm.filteredProcesses)
    }

    func testFilterAndSortProcessesMassiveDataset() {
        // Generate 3,000 synthetic processes
        var items: [ProcessItem] = []
        items.reserveCapacity(3000)

        let categories: [ProcessCategory] = [.apps, .daemons, .system]

        for i in 1...3000 {
            let child1 = ProcessItem(
                id: pid_t(10000 + i * 2),
                ppid: pid_t(i),
                name: "Helper_\(i)_1",
                cpuPercentage: Double((i * 3) % 20),
                memoryBytes: UInt64((i * 1024 * 1024) % (500 * 1024 * 1024)),
                category: categories[i % categories.count]
            )
            let child2 = ProcessItem(
                id: pid_t(10000 + i * 2 + 1),
                ppid: pid_t(i),
                name: "Helper_\(i)_2",
                cpuPercentage: Double((i * 7) % 30),
                memoryBytes: UInt64((i * 2048 * 1024) % (800 * 1024 * 1024)),
                category: categories[(i + 1) % categories.count]
            )

            let parent = ProcessItem(
                id: pid_t(i),
                ppid: 1,
                name: "App_\(i)",
                cpuPercentage: Double(i % 100),
                memoryBytes: UInt64((i * 4096 * 1024) % (1024 * 1024 * 1024)),
                children: [child1, child2],
                category: categories[i % categories.count]
            )
            items.append(parent)
        }

        let start = DispatchTime.now()

        let filtered = DashboardViewModel.filterAndSortProcesses(
            processes: items,
            query: "app_1",
            category: .apps,
            sortField: .cpu,
            sortAscending: false
        )

        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0

        XCTAssertFalse(filtered.isEmpty)
        XCTAssertLessThan(elapsedMs, 200.0, "Filtering 3,000 tree-structured processes must take < 200ms (took \(elapsedMs)ms)")

        // Check descending CPU order
        for idx in 0..<(filtered.count - 1) {
            XCTAssertGreaterThanOrEqual(filtered[idx].totalCPU, filtered[idx + 1].totalCPU)
        }
    }

    func testFilterAndSortProcessesExtremeValues() {
        let p1 = ProcessItem(
            id: -1,
            ppid: 0,
            name: "Extreme_Zero",
            cpuPercentage: 0.0,
            memoryBytes: 0,
            category: .system
        )
        let p2 = ProcessItem(
            id: 1,
            ppid: 0,
            name: "Extreme_High",
            cpuPercentage: 1000.0,
            memoryBytes: UInt64.max,
            category: .system
        )
        let p3 = ProcessItem(
            id: 2,
            ppid: 1,
            name: "🔥 Emoji & RTL \u{202E}Text\u{202C} 🚀",
            cpuPercentage: 50.0,
            memoryBytes: 500 * 1024 * 1024,
            category: .apps
        )
        let p4 = ProcessItem(
            id: 3,
            ppid: 1,
            name: String(repeating: "LongName_", count: 200),
            cpuPercentage: 10.0,
            memoryBytes: 100 * 1024 * 1024,
            category: .daemons
        )

        let processes = [p1, p2, p3, p4]

        for field in [ProcessSortField.cpu, .memory, .name, .pid] {
            for ascending in [true, false] {
                let sorted = DashboardViewModel.filterAndSortProcesses(
                    processes: processes,
                    query: "",
                    category: .all,
                    sortField: field,
                    sortAscending: ascending
                )
                XCTAssertEqual(sorted.count, 4, "Sorting must retain all items without dropping or crashing for field \(field)")
            }
        }

        // Test Unicode / RTL query
        let queryResults = DashboardViewModel.filterAndSortProcesses(
            processes: processes,
            query: "🔥",
            category: .all,
            sortField: .cpu,
            sortAscending: false
        )
        XCTAssertEqual(queryResults.count, 1)
        XCTAssertEqual(queryResults.first?.id, 2)
    }

    func testDeepProcessTreeTotalCPUAggregation() {
        // Construct deep linear chain: 30 levels
        var current = ProcessItem(
            id: 30,
            ppid: 29,
            name: "Leaf",
            cpuPercentage: 5.0,
            memoryBytes: 10 * 1024 * 1024
        )

        for depth in (1...29).reversed() {
            current = ProcessItem(
                id: pid_t(depth),
                ppid: pid_t(depth - 1),
                name: "Node_\(depth)",
                cpuPercentage: 2.0,
                memoryBytes: 10 * 1024 * 1024,
                children: [current]
            )
        }

        // Depth 1 should have totalCPU = 2.0 * 29 + 5.0 = 63.0
        XCTAssertEqual(current.totalCPU, 63.0, accuracy: 0.001)
        // Total memory = 30 * 10MB = 300MB
        XCTAssertEqual(current.totalMemory, 300 * 1024 * 1024)
    }

    // MARK: - 3. AppleSMCConnection & IOHID Sensor Sampling Resilience

    func testAppleSMCConnectionThreadSafety() async {
        let smc = IOKitBridge.AppleSMCConnection.shared

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    _ = smc.isConnected
                    var input = IOKitBridge.AppleSMCConnection.SMCKeyData()
                    var output = IOKitBridge.AppleSMCConnection.SMCKeyData()
                    // Calling SMC with dummy key should return safely with status without crashing
                    input.key = 0x464E756D // 'FNum'
                    input.data8 = 9
                    _ = smc.callSMC(input: &input, output: &output)
                }
            }
        }
    }

    func testAppleSMCConnectionCloseAndReopen() {
        let connection = IOKitBridge.AppleSMCConnection()
        let initialConnected = connection.isConnected

        // Explicitly close
        connection.close()
        XCTAssertFalse(connection.isConnected)

        // Calling callSMC after close should automatically trigger openConnection
        var input = IOKitBridge.AppleSMCConnection.SMCKeyData()
        var output = IOKitBridge.AppleSMCConnection.SMCKeyData()
        input.key = 0x464E756D // 'FNum'
        _ = connection.callSMC(input: &input, output: &output)

        // Should recover connection state if SMC service exists
        if initialConnected {
            XCTAssertTrue(connection.isConnected, "callSMC must reconnect when previously closed")
        }

        connection.close()
    }

    func testIOHIDClientWrapperSamplingResilience() {
        guard let wrapper = IOHIDBridge.ClientWrapper() else {
            return
        }

        // Perform 30 rapid sample iterations
        for _ in 0..<30 {
            let snapshot = wrapper.sample()
            if let snap = snapshot {
                if let socAvg = snap.socDieAverageTemperature {
                    XCTAssertGreaterThanOrEqual(socAvg, 10.0)
                    XCTAssertLessThanOrEqual(socAvg, 125.0)
                }
                if let socPeak = snap.socDiePeakTemperature {
                    XCTAssertGreaterThanOrEqual(socPeak, 10.0)
                    XCTAssertLessThanOrEqual(socPeak, 125.0)
                }
                for (_, temp) in snap.individualDieSensors {
                    XCTAssertGreaterThanOrEqual(temp, 10.0)
                    XCTAssertLessThanOrEqual(temp, 125.0)
                }
            }
        }
    }

    func testRingBufferExtremeAndNilValuesResilience() {
        var ring = RingBuffer<Double>(capacity: 60, initialElement: 0.0)
        XCTAssertEqual(ring.count, 60)

        // Append nil fallback (0.0), extreme highs, and valid numbers
        let testValues: [Double] = [0.0, 120.5, 124.9, 45.0, 60.0, 0.0, 999.0, -10.0]
        for val in testValues {
            ring.append(val)
        }

        XCTAssertEqual(ring.count, 60)
        XCTAssertEqual(ring.last, -10.0)
        XCTAssertEqual(ring.elements.count, 60)
    }

    func testProcessBufferSlabConcurrentStress() async {
        let slab = DarwinMachBridge.ProcessBufferSlab.shared

        await withTaskGroup(of: [DarwinMachBridge.ProcessBasicEntry].self) { group in
            for _ in 0..<30 {
                group.addTask {
                    return slab.listProcesses()
                }
            }

            for await entries in group {
                XCTAssertFalse(entries.isEmpty)
                XCTAssertGreaterThan(entries.count, 10)
            }
        }

        XCTAssertGreaterThanOrEqual(slab.currentByteCapacity, 512 * 1024)
    }

    func testThreadSafeGetpwuid_rConcurrentStress() async {
        let currentUID = getuid()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    let uid: uid_t = (i % 3 == 0) ? 0 : ((i % 3 == 1) ? currentUID : 999_999)
                    let name = DarwinMachBridge.resolveUsername(for: uid)
                    if uid == 0 {
                        XCTAssertEqual(name, "root")
                    } else if uid == 999_999 {
                        XCTAssertNil(name)
                    } else {
                        XCTAssertNotNil(name)
                    }
                }
            }
        }
    }
}
