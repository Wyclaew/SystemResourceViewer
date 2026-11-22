import XCTest
@testable import SystemResourceViewer

final class ExportManagerTests: XCTestCase {
    private func createMockProcesses() -> [ProcessItem] {
        return [
            ProcessItem(
                id: 101,
                name: "Safari",
                cpuPercentage: 15.5,
                memoryBytes: 500 * 1024 * 1024,
                ownerUser: "testuser",
                executablePath: "/Applications/Safari.app/Contents/MacOS/Safari",
                isSuspended: false,
                diskReadBytesPerSecond: 1024 * 1024,
                diskWriteBytesPerSecond: 512 * 1024,
                totalDiskReadBytes: 10 * 1024 * 1024,
                totalDiskWriteBytes: 5 * 1024 * 1024
            ),
            ProcessItem(
                id: 202,
                name: "Terminal, \"Debug\"",
                cpuPercentage: 2.0,
                memoryBytes: 50 * 1024 * 1024,
                ownerUser: "testuser",
                executablePath: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal",
                isSuspended: true
            )
        ]
    }

    private func createMockSystemMetrics(processes: [ProcessItem]) -> SystemMetrics {
        let cpu = CPUMetrics(
            totalUsage: 20.0,
            userPercentage: 12.0,
            systemPercentage: 8.0,
            idlePercentage: 80.0,
            pCoreAverageUsage: 20.0,
            eCoreAverageUsage: 20.0
        )
        let memory = MemoryMetrics(
            totalBytes: 16 * 1024 * 1024 * 1024,
            appMemoryBytes: 4 * 1024 * 1024 * 1024,
            wiredBytes: 2 * 1024 * 1024 * 1024,
            compressedBytes: 2 * 1024 * 1024 * 1024,
            cachedBytes: 4 * 1024 * 1024 * 1024,
            freeBytes: 4 * 1024 * 1024 * 1024,
            pressureLevel: .normal
        )
        let gpu = GPUMetrics(
            deviceUtilization: 25.0,
            allocatedVRAMBytes: 4 * 1024 * 1024 * 1024,
            inUseVRAMBytes: 1024 * 1024 * 1024
        )
        let disk = DiskMetrics(
            volumeName: "Macintosh HD",
            totalBytes: 500 * 1024 * 1024 * 1024,
            freeBytes: 250 * 1024 * 1024 * 1024,
            readBytesPerSecond: 1024 * 1024,
            writeBytesPerSecond: 512 * 1024
        )
        let network = NetworkMetrics(
            downloadBytesPerSecond: 2048,
            uploadBytesPerSecond: 1024,
            primaryInterfaceName: "en0",
            localIPv4: "192.168.1.125"
        )
        return SystemMetrics(
            cpu: cpu,
            gpu: gpu,
            memory: memory,
            disk: disk,
            network: network,
            processes: processes
        )
    }

    private func createMockHardwareProfile() -> HardwareProfile {
        HardwareProfile(
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
            bootTime: Date().addingTimeInterval(-86400 * 2),
            uptimeSeconds: 86400 * 2
        )
    }

    func testExportManagerGenerateCSV() {
        let processes = createMockProcesses()
        let csv = ExportManager.exportProcessCSV(processes: processes)

        XCTAssertTrue(csv.contains("PID,PPID,Name,User,Architecture,Category,Status,CPU(%),Memory(MB),DiskRead(KB/s),DiskWrite(KB/s),Threads,Path"))
        XCTAssertTrue(csv.contains("101,0,Safari,testuser"))
        // Check RFC 4180 escaping for name with comma and quotes: "Terminal, ""Debug"""
        XCTAssertTrue(csv.contains("\"Terminal, \"\"Debug\"\"\""), "Process name with commas and quotes must be escaped per RFC 4180")
    }

    func testExportManagerGenerateJSONTelemetry() throws {
        let processes = createMockProcesses()
        let metrics = createMockSystemMetrics(processes: processes)
        let hardware = createMockHardwareProfile()
        let privacy = PrivacySettings(maskSensitiveArguments: true, allowExternalSocketProbe: true, maskLocalIPAddress: true)

        let jsonString = ExportManager.exportTelemetryJSON(
            metrics: metrics,
            hardwareProfile: hardware,
            privacySettings: privacy
        )

        guard let data = jsonString.data(using: .utf8) else {
            XCTFail("Could not convert JSON string to Data")
            return
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        XCTAssertNotNil(jsonObject)
        XCTAssertNotNil(jsonObject?["cpu"])
        XCTAssertNotNil(jsonObject?["gpu"])
        XCTAssertNotNil(jsonObject?["memory"])
        XCTAssertNotNil(jsonObject?["processes"])

        // Verify IP address was masked
        if let netObj = jsonObject?["network"] as? [String: Any], let ip = netObj["local_ipv4"] as? String {
            XCTAssertFalse(ip.contains("192.168.1.125"), "IP address should be masked")
            XCTAssertTrue(ip.contains("*"), "Masked IP should contain *")
        }
    }

    func testExportManagerGenerateMarkdownSummary() {
        let processes = createMockProcesses()
        let metrics = createMockSystemMetrics(processes: processes)
        let hardware = createMockHardwareProfile()
        let privacy = PrivacySettings(maskSensitiveArguments: false, allowExternalSocketProbe: true, maskLocalIPAddress: false)

        let md = ExportManager.exportMarkdownSummary(
            metrics: metrics,
            hardwareProfile: hardware,
            privacySettings: privacy
        )

        XCTAssertTrue(md.contains("# System Resource Viewer — Diagnostics Report"))
        XCTAssertTrue(md.contains("## Subsystem Telemetry"))
        XCTAssertTrue(md.contains("**GPU**"))
        XCTAssertTrue(md.contains("## Top CPU Processes"))
        XCTAssertTrue(md.contains("Safari"))
    }
}
