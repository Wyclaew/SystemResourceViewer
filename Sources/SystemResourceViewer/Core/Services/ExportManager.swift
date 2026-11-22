import AppKit
import Foundation

/// Centralized manager for generating CSV, JSON, and Markdown diagnostic exports
/// while enforcing PrivacySettings masking for sensitive credentials, arguments, and network IPs.
public enum ExportManager {

    // MARK: - CSV Export (RFC 4180)

    public static func exportProcessCSV(
        processes: [ProcessItem],
        privacySettings: PrivacySettings = .defaultSettings
    ) -> String {
        var lines: [String] = []
        // Header
        lines.append("PID,PPID,Name,User,Architecture,Category,Status,CPU(%),Memory(MB),DiskRead(KB/s),DiskWrite(KB/s),Threads,Path")

        let filtered = privacySettings.hideSystemProcessesByDefault
            ? processes.filter { $0.category != .system && $0.category != .daemons }
            : processes

        for process in filtered {
            let pid = "\(process.id)"
            let ppid = "\(process.ppid)"
            let name = escapeCSV(process.name)
            let user = escapeCSV(process.ownerUser)
            let arch = escapeCSV(process.architecture)
            let cat = escapeCSV(process.category.rawValue)
            let status = process.isSuspended ? "Paused" : "Running"
            let cpu = String(format: "%.1f", process.cpuPercentage)
            let memMB = String(format: "%.1f", Double(process.memoryBytes) / (1024 * 1024))
            let readKBs = String(format: "%.1f", process.diskReadBytesPerSecond / 1024.0)
            let writeKBs = String(format: "%.1f", process.diskWriteBytesPerSecond / 1024.0)
            let threads = "\(process.threadCount)"
            let rawPath = process.executablePath ?? ""
            let sanitizedPath = privacySettings.sanitize(argument: rawPath)
            let escapedPath = escapeCSV(sanitizedPath)

            let row = "\(pid),\(ppid),\(name),\(user),\(arch),\(cat),\(status),\(cpu),\(memMB),\(readKBs),\(writeKBs),\(threads),\(escapedPath)"
            lines.append(row)
        }

        return lines.joined(separator: "\r\n")
    }

    private static func escapeCSV(_ text: String) -> String {
        if text.contains(where: { $0.isNewline || $0 == "," || $0 == "\"" }) || text.contains("\r\n") {
            let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return text
    }

    // MARK: - JSON Telemetry Snapshot

    public static func exportTelemetryJSON(
        metrics: SystemMetrics,
        hardwareProfile: HardwareProfile,
        privacySettings: PrivacySettings = .defaultSettings
    ) -> String {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: metrics.timestamp)

        let sanitizedIPv4 = privacySettings.sanitize(ipv4: metrics.network.localIPv4)

        var processDicts: [[String: Any]] = []
        for p in metrics.processes {
            let path = p.executablePath.map { privacySettings.sanitize(argument: $0) }
            processDicts.append([
                "pid": p.id,
                "ppid": p.ppid,
                "name": p.name,
                "user": p.ownerUser,
                "architecture": p.architecture,
                "category": p.category.rawValue,
                "status": p.isSuspended ? "Paused" : "Running",
                "cpu_percentage": p.cpuPercentage,
                "memory_bytes": p.memoryBytes,
                "threads": p.threadCount,
                "disk_read_bytes_per_sec": p.diskReadBytesPerSecond,
                "disk_write_bytes_per_sec": p.diskWriteBytesPerSecond,
                "path": path as Any
            ])
        }

        let dict: [String: Any] = [
            "export_timestamp": timestamp,
            "system": [
                "model_identifier": hardwareProfile.modelIdentifier,
                "marketing_name": hardwareProfile.marketingModelName,
                "cpu_brand": hardwareProfile.cpuBrand,
                "total_cores": hardwareProfile.totalCores,
                "performance_cores": hardwareProfile.performanceCores,
                "efficiency_cores": hardwareProfile.efficiencyCores,
                "total_memory_bytes": hardwareProfile.totalMemoryBytes,
                "os_version": hardwareProfile.osVersionString,
                "os_build": hardwareProfile.osBuildVersion,
                "kernel": hardwareProfile.kernelRelease,
                "boot_time": formatter.string(from: hardwareProfile.bootTime),
                "uptime_seconds": hardwareProfile.uptimeSeconds
            ],
            "cpu": [
                "total_usage_percent": metrics.cpu.totalUsage,
                "user_percent": metrics.cpu.userPercentage,
                "system_percent": metrics.cpu.systemPercentage,
                "idle_percent": metrics.cpu.idlePercentage,
                "p_core_average_percent": metrics.cpu.pCoreAverageUsage,
                "e_core_average_percent": metrics.cpu.eCoreAverageUsage
            ],
            "gpu": [
                "model_name": metrics.gpu.modelName,
                "device_utilization_percent": metrics.gpu.deviceUtilization,
                "renderer_utilization_percent": metrics.gpu.rendererUtilization,
                "tiler_utilization_percent": metrics.gpu.tilerUtilization,
                "allocated_vram_bytes": metrics.gpu.allocatedVRAMBytes,
                "in_use_vram_bytes": metrics.gpu.inUseVRAMBytes,
                "has_unified_memory": metrics.gpu.hasUnifiedMemory
            ],
            "memory": [
                "total_bytes": metrics.memory.totalBytes,
                "used_bytes": metrics.memory.usedBytes,
                "used_percent": metrics.memory.usedPercentage,
                "free_bytes": metrics.memory.freeBytes,
                "pressure_level": metrics.memory.pressureLevel.rawValue
            ],
            "thermal": [
                "soc_die_temp_celsius": metrics.thermal.socDieTemperature as Any,
                "peak_die_temp_celsius": metrics.thermal.peakDieTemperature as Any,
                "thermal_state": metrics.thermal.thermalStateDescription,
                "is_fanless": metrics.thermal.isFanless
            ],
            "disk": [
                "volume_name": metrics.disk.volumeName,
                "total_bytes": metrics.disk.totalBytes,
                "free_bytes": metrics.disk.freeBytes,
                "used_percent": metrics.disk.usedPercentage,
                "read_bytes_per_sec": metrics.disk.readBytesPerSecond,
                "write_bytes_per_sec": metrics.disk.writeBytesPerSecond
            ],
            "network": [
                "primary_interface": metrics.network.primaryInterfaceName,
                "interface_type": metrics.network.interfaceType.rawValue,
                "local_ipv4": sanitizedIPv4,
                "download_bytes_per_sec": metrics.network.downloadBytesPerSecond,
                "upload_bytes_per_sec": metrics.network.uploadBytesPerSecond
            ],
            "processes": processDicts
        ]

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }

    // MARK: - Markdown Summary for Clipboard

    public static func exportMarkdownSummary(
        metrics: SystemMetrics,
        hardwareProfile: HardwareProfile,
        activeAlerts: [SystemAlert] = [],
        privacySettings: PrivacySettings = .defaultSettings
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        let dateString = formatter.string(from: metrics.timestamp)

        let sanitizedIP = privacySettings.sanitize(ipv4: metrics.network.localIPv4)

        var md = """
        # System Resource Viewer — Diagnostics Report
        **Generated**: \(dateString)

        ## System Hardware & OS
        - **Hardware Model**: \(hardwareProfile.marketingModelName) (\(hardwareProfile.modelIdentifier))
        - **Processor**: \(hardwareProfile.cpuBrand) (\(hardwareProfile.totalCores) cores: \(hardwareProfile.performanceCores)P + \(hardwareProfile.efficiencyCores)E)
        - **Memory**: \(Formatters.formatBytes(hardwareProfile.totalMemoryBytes))
        - **macOS**: \(hardwareProfile.osVersionString) (Build \(hardwareProfile.osBuildVersion))
        - **Kernel**: \(hardwareProfile.kernelRelease)
        - **Uptime**: \(Formatters.formatUptime(hardwareProfile.uptimeSeconds))

        ## Subsystem Telemetry
        | Subsystem | Metric | Value |
        | :--- | :--- | :--- |
        | **CPU** | Total Load | \(String(format: "%.1f%%", metrics.cpu.totalUsage)) |
        | **GPU** | Model / Load | \(metrics.gpu.modelName) (\(String(format: "%.1f%%", metrics.gpu.deviceUtilization))) |
        | **Memory** | Usage | \(String(format: "%.1f%%", metrics.memory.usedPercentage)) (\(Formatters.formatBytes(metrics.memory.usedBytes)) / \(Formatters.formatBytes(metrics.memory.totalBytes))) |
        | **Memory** | Pressure | \(metrics.memory.pressureLevel.rawValue) |
        | **Thermals** | State | \(metrics.thermal.thermalStateDescription) |
        | **Thermals** | SoC Temp | \(metrics.thermal.socDieTemperature.map { String(format: "%.1f°C", $0) } ?? "N/A") |
        | **Storage** | Volume '\(metrics.disk.volumeName)' | \(String(format: "%.1f%% used", metrics.disk.usedPercentage)) |
        | **Storage I/O** | Read / Write | \(Formatters.formatSpeed(metrics.disk.readBytesPerSecond)) / \(Formatters.formatSpeed(metrics.disk.writeBytesPerSecond)) |
        | **Network** | Interface | \(metrics.network.primaryInterfaceName) (\(metrics.network.interfaceType.rawValue)) |
        | **Network** | Local IP | \(sanitizedIP) |
        | **Network** | Throughput | ↓ \(Formatters.formatSpeed(metrics.network.downloadBytesPerSecond)) / ↑ \(Formatters.formatSpeed(metrics.network.uploadBytesPerSecond)) |

        """

        if !activeAlerts.isEmpty {
            md += "\n## Active Resource Alerts\n"
            for alert in activeAlerts {
                md += "- [\(alert.severity.rawValue)] **\(alert.title)**: \(alert.message)\n"
            }
        }

        // Top 5 CPU Processes
        let topCPU = metrics.processes.sorted { $0.totalCPU > $1.totalCPU }.prefix(5)
        if !topCPU.isEmpty {
            md += "\n## Top CPU Processes\n"
            md += "| PID | Name | User | CPU % | Memory | Status |\n"
            md += "| :--- | :--- | :--- | :--- | :--- | :--- |\n"
            for p in topCPU {
                md += "| \(p.id) | \(p.name) | \(p.ownerUser) | \(p.formattedCPU) | \(p.formattedMemory) | \(p.isSuspended ? "Paused" : "Running") |\n"
            }
        }

        // Top 5 Memory Processes
        let topMem = metrics.processes.sorted { $0.totalMemory > $1.totalMemory }.prefix(5)
        if !topMem.isEmpty {
            md += "\n## Top Memory Processes\n"
            md += "| PID | Name | User | Memory | CPU % | Status |\n"
            md += "| :--- | :--- | :--- | :--- | :--- | :--- |\n"
            for p in topMem {
                md += "| \(p.id) | \(p.name) | \(p.ownerUser) | \(p.formattedMemory) | \(p.formattedCPU) | \(p.isSuspended ? "Paused" : "Running") |\n"
            }
        }

        return md
    }

    // MARK: - Clipboard Utility

    public static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
