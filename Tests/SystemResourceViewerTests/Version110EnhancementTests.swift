import XCTest
import AppKit
@testable import SystemResourceViewer

final class Version110EnhancementTests: XCTestCase {

    // MARK: - 1. IOKit Numeric Bridging Resilience Tests

    func testBatteryTelemetryNSNumberExtraction() {
        // Simulates macOS kernel IORegistry boxing numbers as __NSCFNumber / NSNumber
        let mockBatteryDict: [String: Any] = [
            "CycleCount": NSNumber(value: 142),
            "MaxCapacity": NSNumber(value: 4800),
            "DesignCapacity": NSNumber(value: 5000),
            "InstantAmperage": NSNumber(value: -1250),
            "Voltage": NSNumber(value: 12600)
        ]

        let parsed = IOKitBridge.parseBatteryProperties(from: mockBatteryDict)

        XCTAssertEqual(parsed.cycleCount, 142)
        XCTAssertNotNil(parsed.healthPercentage)
        // 4800 / 5000 = 96.0%
        XCTAssertEqual(parsed.healthPercentage!, 96.0, accuracy: 0.01)

        XCTAssertNotNil(parsed.powerDrawWatts)
        // abs(-1250 * 12600) / 1,000,000 = 15.75 -> rounded to 15.8 W
        XCTAssertEqual(parsed.powerDrawWatts!, 15.8, accuracy: 0.1)
    }

    func testBatteryTelemetryAlternativeAmperageKey() {
        let mockBatteryDict: [String: Any] = [
            "MaxCapacity": NSNumber(value: 5000),
            "DesignCapacity": NSNumber(value: 5000),
            "Amperage": NSNumber(value: -800),
            "Voltage": NSNumber(value: 12000)
        ]

        let parsed = IOKitBridge.parseBatteryProperties(from: mockBatteryDict)
        XCTAssertNotNil(parsed.powerDrawWatts)
        // abs(-800 * 12000) / 1,000,000 = 9.6 W
        XCTAssertEqual(parsed.powerDrawWatts!, 9.6, accuracy: 0.1)
    }

    func testDiskIOBytesNSNumberExtraction() {
        let mockStats: [String: Any] = [
            "Bytes (Read)": NSNumber(value: 27_934_879_145_984 as UInt64),
            "Bytes (Write)": NSNumber(value: 14_500_000_000_000 as UInt64)
        ]

        let parsed = IOKitBridge.parseDiskIOStats(from: mockStats)
        XCTAssertEqual(parsed.read, 27_934_879_145_984)
        XCTAssertEqual(parsed.write, 14_500_000_000_000)
    }

    func testDiskIOBytesInt64FallbackExtraction() {
        let mockStats: [String: Any] = [
            "Bytes (Read)": Int64(1024 * 1024),
            "Bytes (Write)": Int64(2048 * 1024)
        ]

        let parsed = IOKitBridge.parseDiskIOStats(from: mockStats)
        XCTAssertEqual(parsed.read, 1024 * 1024)
        XCTAssertEqual(parsed.write, 2048 * 1024)
    }

    // MARK: - 2. ProcessItem Equality Completeness & Bounded IconCache Tests

    func testProcessItemEqualityIncludesDiskRates() {
        let p1 = ProcessItem(
            id: 501,
            name: "DataWorker",
            cpuPercentage: 10.0,
            memoryBytes: 100 * 1024 * 1024,
            diskReadBytesPerSecond: 1024,
            diskWriteBytesPerSecond: 2048
        )

        // Identical to p1
        let p2 = ProcessItem(
            id: 501,
            name: "DataWorker",
            cpuPercentage: 10.0,
            memoryBytes: 100 * 1024 * 1024,
            diskReadBytesPerSecond: 1024,
            diskWriteBytesPerSecond: 2048
        )

        // Different diskReadBytesPerSecond
        let p3 = ProcessItem(
            id: 501,
            name: "DataWorker",
            cpuPercentage: 10.0,
            memoryBytes: 100 * 1024 * 1024,
            diskReadBytesPerSecond: 9999,
            diskWriteBytesPerSecond: 2048
        )

        // Different diskWriteBytesPerSecond
        let p4 = ProcessItem(
            id: 501,
            name: "DataWorker",
            cpuPercentage: 10.0,
            memoryBytes: 100 * 1024 * 1024,
            diskReadBytesPerSecond: 1024,
            diskWriteBytesPerSecond: 9999
        )

        XCTAssertEqual(p1, p2, "ProcessItems with identical properties must be equal")
        XCTAssertNotEqual(p1, p3, "ProcessItems with differing diskReadBytesPerSecond must NOT be equal")
        XCTAssertNotEqual(p1, p4, "ProcessItems with differing diskWriteBytesPerSecond must NOT be equal")
    }

    func testIconCacheBoundedCapacity() {
        let cache = ProcessItem.IconCache(maxCapacity: 5)
        let sampleImage = NSImage()

        for i in 1...5 {
            cache.setIcon(sampleImage, forPath: "/app/path/\(i)")
        }
        XCTAssertEqual(cache.count, 5)

        // Adding 6th item should purge prior storage and retain the new item
        cache.setIcon(sampleImage, forPath: "/app/path/6")
        XCTAssertEqual(cache.count, 1)
        XCTAssertNotNil(cache.icon(forPath: "/app/path/6"))
        XCTAssertNil(cache.icon(forPath: "/app/path/1"))
    }

    // MARK: - 3. ExportManager GPU Subsystem Parity Tests

    func testExportManagerJSONIncludesGPUSubsystem() throws {
        let gpu = GPUMetrics(
            deviceUtilization: 33.5,
            rendererUtilization: 28.0,
            tilerUtilization: 12.0,
            allocatedVRAMBytes: 8 * 1024 * 1024 * 1024,
            inUseVRAMBytes: 2 * 1024 * 1024 * 1024,
            coreCount: 18,
            modelName: "Apple M3 Pro",
            hasUnifiedMemory: true
        )

        let metrics = SystemMetrics(
            cpu: CPUMetrics(totalUsage: 15.0),
            gpu: gpu,
            memory: MemoryMetrics(totalBytes: 18 * 1024 * 1024 * 1024),
            disk: DiskMetrics(volumeName: "Macintosh HD"),
            network: NetworkMetrics(),
            processes: []
        )

        let hardware = HardwareProfile(
            modelIdentifier: "Mac15,6",
            marketingModelName: "MacBook Pro (14-inch, M3 Pro, Nov 2023)",
            cpuBrand: "Apple M3 Pro",
            totalCores: 12,
            performanceCores: 6,
            efficiencyCores: 6,
            totalMemoryBytes: 18 * 1024 * 1024 * 1024,
            osVersionString: "macOS 14.5",
            osBuildVersion: "23F79",
            kernelRelease: "Darwin 23.5.0",
            bootTime: Date(),
            uptimeSeconds: 3600
        )

        let json = ExportManager.exportTelemetryJSON(metrics: metrics, hardwareProfile: hardware)
        guard let data = json.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            XCTFail("Failed to serialize or parse JSON data")
            return
        }

        guard let gpuDict = dict["gpu"] as? [String: Any] else {
            XCTFail("Missing 'gpu' dictionary in exportTelemetryJSON")
            return
        }

        XCTAssertEqual(gpuDict["model_name"] as? String, "Apple M3 Pro")
        XCTAssertEqual(gpuDict["device_utilization_percent"] as? Double, 33.5)
        XCTAssertEqual(gpuDict["renderer_utilization_percent"] as? Double, 28.0)
        XCTAssertEqual(gpuDict["tiler_utilization_percent"] as? Double, 12.0)
        XCTAssertEqual(gpuDict["allocated_vram_bytes"] as? Int, 8 * 1024 * 1024 * 1024)
        XCTAssertEqual(gpuDict["in_use_vram_bytes"] as? Int, 2 * 1024 * 1024 * 1024)
        XCTAssertEqual(gpuDict["has_unified_memory"] as? Bool, true)
    }

    func testExportManagerMarkdownIncludesGPURow() {
        let gpu = GPUMetrics(
            deviceUtilization: 42.0,
            modelName: "Apple M2 Max"
        )

        let metrics = SystemMetrics(
            cpu: CPUMetrics(totalUsage: 25.0),
            gpu: gpu,
            memory: MemoryMetrics(totalBytes: 32 * 1024 * 1024 * 1024),
            disk: DiskMetrics(volumeName: "Macintosh HD"),
            network: NetworkMetrics(),
            processes: []
        )

        let hardware = HardwareProfile(
            modelIdentifier: "Mac14,6",
            marketingModelName: "MacBook Pro (16-inch, 2023)",
            cpuBrand: "Apple M2 Max",
            totalCores: 12,
            performanceCores: 8,
            efficiencyCores: 4,
            totalMemoryBytes: 32 * 1024 * 1024 * 1024,
            osVersionString: "macOS 14.5",
            osBuildVersion: "23F79",
            kernelRelease: "Darwin 23.5.0",
            bootTime: Date(),
            uptimeSeconds: 7200
        )

        let md = ExportManager.exportMarkdownSummary(metrics: metrics, hardwareProfile: hardware)
        XCTAssertTrue(md.contains("| **GPU** | Model / Load | Apple M2 Max (42.0%) |"))
    }

    // MARK: - 4. Apple Silicon Model Name Resolution Tests

    func testAppleSiliconModelNameMappings() {
        XCTAssertEqual(DarwinMachBridge.resolveMacMarketingName(for: "Mac14,2"), "MacBook Air (M2, 2022)")
        XCTAssertEqual(DarwinMachBridge.resolveMacMarketingName(for: "Mac14,3"), "Mac mini (M2, 2023)")
        XCTAssertEqual(DarwinMachBridge.resolveMacMarketingName(for: "Mac14,6"), "MacBook Pro (16-inch, M2 Max, 2023)")
        XCTAssertEqual(DarwinMachBridge.resolveMacMarketingName(for: "Mac14,15"), "MacBook Air (15-inch, M2, 2023)")
        XCTAssertEqual(DarwinMachBridge.resolveMacMarketingName(for: "Mac15,6"), "MacBook Pro (14-inch, M3 Pro, Nov 2023)")
        XCTAssertEqual(DarwinMachBridge.resolveMacMarketingName(for: "Mac15,12"), "MacBook Air (13-inch, M3, 2024)")
        XCTAssertEqual(DarwinMachBridge.resolveMacMarketingName(for: "Mac15,13"), "MacBook Air (15-inch, M3, 2024)")
        XCTAssertEqual(DarwinMachBridge.resolveMacMarketingName(for: "Mac16,1"), "MacBook Pro (14-inch, M4)")
        XCTAssertEqual(DarwinMachBridge.resolveMacMarketingName(for: "Mac16,10"), "Mac mini (M4, 2024)")
        XCTAssertEqual(DarwinMachBridge.resolveMacMarketingName(for: "MacBookAir10,1"), "MacBook Air (M1, 2020)")
        XCTAssertEqual(DarwinMachBridge.resolveMacMarketingName(for: "UnknownMac99,1"), "Mac (UnknownMac99,1)")
    }

    // MARK: - 5. DashboardViewModel Filter Reset & Version Fallback Tests

    @MainActor
    func testDashboardViewModelClearFilters() {
        let vm = DashboardViewModel(interval: 5.0)
        vm.searchText = "WindowServer"
        vm.selectedCategory = .system

        XCTAssertEqual(vm.searchText, "WindowServer")
        XCTAssertEqual(vm.selectedCategory, .system)

        vm.clearFilters()

        XCTAssertEqual(vm.searchText, "")
        XCTAssertEqual(vm.selectedCategory, .all)
    }

    @MainActor
    func testDashboardViewModelVersionFallback() {
        let vm = DashboardViewModel(interval: 5.0)
        XCTAssertEqual(vm.appVersion, "1.1.0")
    }

    // MARK: - 6. UpdateChecker Target Repository and v1.1.0 Semantic Checks

    func testUpdateCheckerTargetRepository() async {
        let expectedHost = "https://api.github.com/repos/Wyclaew/SystemResourceViewer/releases/latest"
        final class URLBox: @unchecked Sendable {
            var url: URL?
        }
        let box = URLBox()

        MockURLProtocol.requestHandler = { request in
            box.url = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let sample = """
            {
                "tag_name": "v1.2.0",
                "name": "Version 1.2.0",
                "body": "Update.",
                "html_url": "https://github.com/Wyclaew/SystemResourceViewer/releases/tag/v1.2.0",
                "published_at": "2026-11-22T00:00:00Z"
            }
            """.data(using: .utf8)!
            return (response, sample)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let service = UpdateCheckerService(session: session)
        let release = await service.checkForUpdates(currentVersion: "1.1.0")

        XCTAssertNotNil(release)
        XCTAssertEqual(box.url?.absoluteString, expectedHost, "UpdateCheckerService default repo must be Wyclaew/SystemResourceViewer")
    }

    func testUpdateCheckerSemanticVersionV110Comparison() {
        // v1.1.0 running against newer remote tags
        XCTAssertTrue(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0", remoteTag: "v1.1.1"))
        XCTAssertTrue(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0", remoteTag: "v1.2.0"))
        XCTAssertTrue(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0", remoteTag: "2.0.0"))

        // v1.1.0 running against equal or older remote tags
        XCTAssertFalse(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0", remoteTag: "v1.1.0"))
        XCTAssertFalse(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0", remoteTag: "1.1.0"))
        XCTAssertFalse(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0", remoteTag: "v1.0.0"))
        XCTAssertFalse(UpdateCheckerLogic.isUpdateAvailable(current: "1.1.0", remoteTag: "v1.0.9"))
    }

    // MARK: - 7. Process BSD Info Guard Test

    func testProcessBSDInfoSecZeroProtection() {
        // PID 0 or negative PIDs should safely return nil
        XCTAssertNil(DarwinMachBridge.fetchProcessBSDInfo(for: 0))
        XCTAssertNil(DarwinMachBridge.fetchProcessBSDInfo(for: -1))
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
