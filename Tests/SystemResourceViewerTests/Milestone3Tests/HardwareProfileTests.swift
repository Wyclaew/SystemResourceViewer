import XCTest
@testable import SystemResourceViewer

final class HardwareProfileTests: XCTestCase {
    func testFetchHardwareProfileLiveHost() {
        let profile = DarwinMachBridge.fetchHardwareProfile()
        XCTAssertFalse(profile.modelIdentifier.isEmpty, "Model identifier should not be empty")
        XCTAssertFalse(profile.cpuBrand.isEmpty, "CPU brand should not be empty")
        XCTAssertGreaterThan(profile.totalCores, 0, "Total cores must be > 0")
        XCTAssertGreaterThan(profile.totalMemoryBytes, 0, "Total memory must be > 0")
        XCTAssertFalse(profile.osVersionString.isEmpty, "OS version should not be empty")
        XCTAssertFalse(profile.osBuildVersion.isEmpty, "OS build should not be empty")
        XCTAssertGreaterThan(profile.uptimeSeconds, 0, "Uptime seconds must be > 0")
        XCTAssertLessThanOrEqual(profile.bootTime, Date(), "Boot time must be in the past")
    }

    func testFetchBootTimeAndUptime() {
        let bootTime = DarwinMachBridge.fetchBootTime()
        XCTAssertNotNil(bootTime, "fetchBootTime should return non-nil on macOS")
        if let bt = bootTime {
            XCTAssertLessThan(bt, Date(), "Boot time must be earlier than now")
        }

        let uptime = DarwinMachBridge.fetchSystemUptime()
        XCTAssertGreaterThan(uptime, 0, "Uptime must be positive")
    }

    func testResolveMacMarketingName() {
        XCTAssertEqual(DarwinMachBridge.resolveMacMarketingName(for: "Mac14,2"), "MacBook Air (M2, 2022)")
        XCTAssertEqual(DarwinMachBridge.resolveMacMarketingName(for: "Mac14,7"), "MacBook Pro (13-inch, M2, 2022)")
        XCTAssertEqual(DarwinMachBridge.resolveMacMarketingName(for: "Mac15,3"), "MacBook Pro (14-inch, Nov 2023)")
        XCTAssertEqual(DarwinMachBridge.resolveMacMarketingName(for: "Macmini9,1"), "Mac mini (M1, 2020)")
        XCTAssertEqual(DarwinMachBridge.resolveMacMarketingName(for: "UnknownDevice,1"), "Mac (UnknownDevice,1)")
    }

    func testHardwareProfileMarkdownReport() {
        let profile = HardwareProfile(
            modelIdentifier: "Mac14,6",
            marketingModelName: "MacBook Pro (16-inch, 2023)",
            cpuBrand: "Apple M2 Max",
            totalCores: 12,
            performanceCores: 8,
            efficiencyCores: 4,
            totalMemoryBytes: 32 * 1024 * 1024 * 1024,
            osVersionString: "macOS 14.5 (23F79)",
            osBuildVersion: "23F79",
            kernelRelease: "Darwin Kernel Version 23.5.0",
            bootTime: Date().addingTimeInterval(-86400 * 2), // 2 days ago
            uptimeSeconds: 86400 * 2
        )

        let report = profile.generateReport()
        XCTAssertTrue(report.contains("# System Hardware & OS Profile"))
        XCTAssertTrue(report.contains("Apple M2 Max"))
        XCTAssertTrue(report.contains("MacBook Pro (16-inch, 2023)"))
        XCTAssertTrue(report.contains("32.0 GB"))
        XCTAssertTrue(report.contains("macOS 14.5 (23F79)"))
        XCTAssertTrue(report.contains("8 Performance + 4 Efficiency"))
    }

    func testFormatUptime() {
        // 1 day, 2 hours, 3 minutes, 4 seconds = 86400 + 7200 + 180 + 4 = 93784 seconds
        let formatted = Formatters.formatUptime(93784)
        XCTAssertTrue(formatted.contains("1d 2h 3m") || formatted.contains("1d 2h"))

        // Less than an hour (45m 12s)
        let formattedMinutes = Formatters.formatUptime(45 * 60 + 12)
        XCTAssertTrue(formattedMinutes.contains("45m"))
    }
}
