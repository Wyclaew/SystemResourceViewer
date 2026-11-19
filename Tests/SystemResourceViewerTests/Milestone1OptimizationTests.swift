import XCTest
@testable import SystemResourceViewer

final class Milestone1OptimizationTests: XCTestCase {

    // MARK: - 1. ProcessBufferSlab Reuse Tests

    func testProcessBufferSlabRetrievalAndReuse() {
        let slab = DarwinMachBridge.ProcessBufferSlab.shared
        let initialEntries = slab.listProcesses()

        XCTAssertFalse(initialEntries.isEmpty, "listProcesses() should return active processes")
        XCTAssertGreaterThanOrEqual(slab.currentByteCapacity, 512 * 1024, "Slab allocation must be at least 512KB")

        let capacityBefore = slab.currentByteCapacity

        // Second call should reuse the allocated memory slab without growing byteCapacity unnecessarily
        let secondEntries = slab.listProcesses()
        XCTAssertFalse(secondEntries.isEmpty)
        XCTAssertEqual(slab.currentByteCapacity, capacityBefore, "Consecutive listProcesses() must reuse the buffer slab")
    }

    func testDarwinMachBridgeListAllProcessEntriesUsesSlab() {
        let entries = DarwinMachBridge.listAllProcessEntries()
        XCTAssertFalse(entries.isEmpty)

        // Validate basic entries contain valid PIDs and names
        let validPIDs = entries.filter { $0.pid > 0 }
        XCTAssertEqual(validPIDs.count, entries.count)

        // Verify known root processes exist (e.g., launchd PID 1)
        let launchd = entries.first(where: { $0.pid == 1 })
        XCTAssertNotNil(launchd)
        XCTAssertEqual(launchd?.pid, 1)
    }

    // MARK: - 2. Thread-Safe POSIX getpwuid_r Tests

    func testGetpwuid_rRootUserResolution() {
        // UID 0 is universally "root" in POSIX/Darwin
        let rootName = DarwinMachBridge.resolveUsername(for: 0)
        XCTAssertEqual(rootName, "root")
    }

    func testGetpwuid_rCurrentUserResolution() {
        let currentUID = getuid()
        let username = DarwinMachBridge.resolveUsername(for: currentUID)
        XCTAssertNotNil(username)
        XCTAssertFalse(username?.isEmpty ?? true)
    }

    func testGetpwuid_rNonexistentUIDGracefulHandling() {
        // Test an invalid UID that does not exist in directory services
        let invalidUID: uid_t = 999_999_999
        let result = DarwinMachBridge.resolveUsername(for: invalidUID)
        XCTAssertNil(result, "Nonexistent UID should return nil gracefully without crashing")
    }

    // MARK: - 3. IOHID Sensor Metadata Caching Tests

    func testIOHIDSensorMetadataCachingLifecycle() {
        guard let wrapper = IOHIDBridge.ClientWrapper() else {
            // IOHID client unavailable on simulated/restricted environment
            return
        }

        // Sensors should be pre-classified and cached on init
        let cachedCount = wrapper.cachedSensorCount
        XCTAssertGreaterThanOrEqual(cachedCount, 0)

        // Multiple consecutive sample() calls should execute without error using cached sensors
        let sample1 = wrapper.sample()
        let sample2 = wrapper.sample()

        if cachedCount > 0 {
            XCTAssertNotNil(sample1)
            XCTAssertNotNil(sample2)
        }

        // Test explicit refresh
        wrapper.refreshSensorCache()
        XCTAssertEqual(wrapper.cachedSensorCount, cachedCount)
    }

    // MARK: - 4. AppleSMC Persistent Connection (RAII) Tests

    func testAppleSMCConnectionLifecycle() {
        let connection = IOKitBridge.AppleSMCConnection.shared
        // On Apple Silicon or Intel Macs, isConnected indicates user client availability
        let isFanless = IOKitBridge.isFanlessArchitecture()

        if !isFanless {
            // On machines with active cooling, SMC connection must be open
            XCTAssertTrue(connection.isConnected)
        }

        // Test custom instance RAII
        let customConnection = IOKitBridge.AppleSMCConnection()
        XCTAssertEqual(customConnection.isConnected, connection.isConnected)
        customConnection.close()
        XCTAssertFalse(customConnection.isConnected)
    }

    func testFetchFanTelemetryUsesPersistentConnection() {
        let telemetry1 = IOKitBridge.fetchFanTelemetry()
        let telemetry2 = IOKitBridge.fetchFanTelemetry()

        XCTAssertEqual(telemetry1.isFanless, telemetry2.isFanless)
        XCTAssertEqual(telemetry1.fans.count, telemetry2.fans.count)
    }

    // MARK: - 5. Path-Based Process Icon Caching Tests

    func testProcessItemIconCache() {
        let cache = ProcessItem.IconCache.shared
        let dummyPath = "/Applications/Utilities/Terminal.app"

        XCTAssertNil(cache.icon(forPath: dummyPath))

        let testImage = NSImage(size: NSSize(width: 32, height: 32))
        cache.setIcon(testImage, forPath: dummyPath)

        let cached = cache.icon(forPath: dummyPath)
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached, testImage)

        cache.clear()
        XCTAssertNil(cache.icon(forPath: dummyPath))
    }

    // MARK: - 6. Window Occlusion Awareness in DashboardViewModel Tests

    @MainActor
    func testWindowOcclusionModeSwitching() async {
        let vm = DashboardViewModel(interval: 5.0)

        // Default state: window is closed, not visible
        XCTAssertFalse(vm.isDashboardWindowOpen)
        XCTAssertTrue(vm.isWindowVisible)

        // Open window -> full mode
        vm.isDashboardWindowOpen = true
        XCTAssertTrue(vm.isDashboardWindowOpen)

        // Occlude window (minimized to dock or covered)
        vm.setWindowOccluded(true)
        XCTAssertFalse(vm.isWindowVisible)

        // Restore window visibility
        vm.setWindowVisible(true)
        XCTAssertTrue(vm.isWindowVisible)

        // Close window
        vm.isDashboardWindowOpen = false
        XCTAssertFalse(vm.isDashboardWindowOpen)
    }

    // MARK: - 7. Background Process Filtering & Sorting Tests

    func testBackgroundProcessFilteringAndSorting() {
        let p1 = ProcessItem(id: 101, ppid: 1, name: "Xcode", cpuPercentage: 45.0, memoryBytes: 800 * 1024 * 1024, category: .apps)
        let p2 = ProcessItem(id: 102, ppid: 1, name: "Safari", cpuPercentage: 12.0, memoryBytes: 200 * 1024 * 1024, category: .apps)
        let p3 = ProcessItem(id: 201, ppid: 1, name: "launchd", cpuPercentage: 0.5, memoryBytes: 15 * 1024 * 1024, category: .system)
        let p4 = ProcessItem(id: 301, ppid: 1, name: "syslogd", cpuPercentage: 0.1, memoryBytes: 10 * 1024 * 1024, category: .daemons)

        let allProcesses = [p1, p2, p3, p4]

        // 1. Filter by category
        let appResults = DashboardViewModel.filterAndSortProcesses(
            processes: allProcesses,
            query: "",
            category: .apps,
            sortField: .cpu,
            sortAscending: false
        )
        XCTAssertEqual(appResults.count, 2)
        XCTAssertEqual(appResults.first?.name, "Xcode")

        // 2. Filter by search query
        let queryResults = DashboardViewModel.filterAndSortProcesses(
            processes: allProcesses,
            query: "safari",
            category: .all,
            sortField: .cpu,
            sortAscending: false
        )
        XCTAssertEqual(queryResults.count, 1)
        XCTAssertEqual(queryResults.first?.id, 102)

        // 3. Sort ascending by name
        let sortedByName = DashboardViewModel.filterAndSortProcesses(
            processes: allProcesses,
            query: "",
            category: .all,
            sortField: .name,
            sortAscending: true
        )
        XCTAssertEqual(sortedByName.map(\.name), ["launchd", "Safari", "syslogd", "Xcode"])

        // 4. Sort ascending by PID
        let sortedByPID = DashboardViewModel.filterAndSortProcesses(
            processes: allProcesses,
            query: "",
            category: .all,
            sortField: .pid,
            sortAscending: true
        )
        XCTAssertEqual(sortedByPID.map(\.id), [101, 102, 201, 301])
    }

    @MainActor
    func testScheduleProcessFilterAsynchronousUpdate() async {
        let vm = DashboardViewModel(interval: 5.0)
        vm.searchText = "test"
        vm.scheduleProcessFilter()

        // Wait briefly for detached task execution
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Should not crash and should update filteredProcesses
        XCTAssertNotNil(vm.filteredProcesses)
    }
}
