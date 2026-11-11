import XCTest
@testable import SystemResourceViewer

final class CrossFeatureFilterTests: XCTestCase {

    func testCategoryAndSearchCompoundFiltering() {
        let app1 = ProcessItem(id: 100, ppid: 1, name: "Safari", bundleIdentifier: "com.apple.Safari", cpuPercentage: 4.0, memoryBytes: 200 * 1024 * 1024)
        let app2 = ProcessItem(id: 101, ppid: 1, name: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap", cpuPercentage: 10.0, memoryBytes: 800 * 1024 * 1024)
        let daemon = ProcessItem(id: 200, ppid: 1, name: "syslogd", bundleIdentifier: nil, cpuPercentage: 0.1, memoryBytes: 10 * 1024 * 1024)

        let processes = [app1, app2, daemon]

        // 1. Category .apps + search "saf" -> only Safari
        let result1 = ProcessFilterHelper.filter(processes: processes, category: .apps, searchQuery: "saf")
        XCTAssertEqual(result1.count, 1)
        XCTAssertEqual(result1.first?.name, "Safari")

        // 2. Category .highLoad + search "slack" -> only Slack (CPU > 5% and Memory > 500MB)
        let result2 = ProcessFilterHelper.filter(processes: processes, category: .highLoad, searchQuery: "slack")
        XCTAssertEqual(result2.count, 1)
        XCTAssertEqual(result2.first?.name, "Slack")

        // 3. Category .apps + search "syslogd" -> empty (daemon is not in apps)
        let result3 = ProcessFilterHelper.filter(processes: processes, category: .apps, searchQuery: "syslogd")
        XCTAssertTrue(result3.isEmpty)
    }

    func testConcurrentMultiServicePolling() async {
        let cpuService = CPUMonitorService()
        let memService = MemoryMonitorService()
        let diskPowerService = DiskAndPowerService()
        let netService = NetworkMonitorService()

        async let cpu = cpuService.pollCPUMetrics(topProcesses: [])
        async let mem = memService.pollMemoryMetrics(topProcesses: [])
        async let diskPower = diskPowerService.pollDiskAndPower()
        async let net = netService.pollNetworkMetrics()

        let (c, m, dp, n) = await (cpu, mem, diskPower, net)

        XCTAssertNotNil(c)
        XCTAssertGreaterThan(m.totalBytes, 0)
        XCTAssertGreaterThan(dp.0.totalBytes, 0)
        XCTAssertFalse(n.primaryInterfaceName.isEmpty)
    }
}
