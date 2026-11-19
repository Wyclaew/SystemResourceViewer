import AppKit
import Foundation

/// Comprehensive snapshot of low-level Mach and Darwin process diagnostics for ProcessInspectorView.
public struct ProcessDetailItem: Identifiable, Sendable {
    public let id: pid_t
    public let ppid: pid_t
    public let name: String
    public let bundleIdentifier: String?
    public let executablePath: String?
    public let ownerUser: String
    public let architecture: String
    public let isRosetta: Bool
    public let isProtected: Bool
    public let isSuspended: Bool
    public let category: ProcessCategory

    // CPU & Threads
    public let cpuPercentage: Double
    public let threadCount: Int
    public let userTimeNs: UInt64
    public let systemTimeNs: UInt64

    // Memory
    public let residentBytes: UInt64
    public let virtualBytes: UInt64

    // Mach & Kernel Diagnostics
    public let openFileDescriptorsCount: Int?
    public let startTime: Date?
    public let contextSwitches: UInt64
    public let faults: UInt64
    public let pageins: UInt64
    public let cowFaults: UInt64
    public let messagesSent: UInt64
    public let messagesReceived: UInt64
    public let machSyscalls: UInt64
    public let unixSyscalls: UInt64

    // Disk I/O
    public let diskReadBytesPerSecond: Double
    public let diskWriteBytesPerSecond: Double
    public let totalDiskReadBytes: UInt64
    public let totalDiskWriteBytes: UInt64

    public init(
        id: pid_t,
        ppid: pid_t,
        name: String,
        bundleIdentifier: String? = nil,
        executablePath: String? = nil,
        ownerUser: String = "root",
        architecture: String = "Apple Silicon",
        isRosetta: Bool = false,
        isProtected: Bool = false,
        isSuspended: Bool = false,
        category: ProcessCategory = .apps,
        cpuPercentage: Double = 0.0,
        threadCount: Int = 1,
        userTimeNs: UInt64 = 0,
        systemTimeNs: UInt64 = 0,
        residentBytes: UInt64 = 0,
        virtualBytes: UInt64 = 0,
        openFileDescriptorsCount: Int? = nil,
        startTime: Date? = nil,
        contextSwitches: UInt64 = 0,
        faults: UInt64 = 0,
        pageins: UInt64 = 0,
        cowFaults: UInt64 = 0,
        messagesSent: UInt64 = 0,
        messagesReceived: UInt64 = 0,
        machSyscalls: UInt64 = 0,
        unixSyscalls: UInt64 = 0,
        diskReadBytesPerSecond: Double = 0.0,
        diskWriteBytesPerSecond: Double = 0.0,
        totalDiskReadBytes: UInt64 = 0,
        totalDiskWriteBytes: UInt64 = 0
    ) {
        self.id = id
        self.ppid = ppid
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.executablePath = executablePath
        self.ownerUser = ownerUser
        self.architecture = architecture
        self.isRosetta = isRosetta
        self.isProtected = isProtected
        self.isSuspended = isSuspended
        self.category = category
        self.cpuPercentage = cpuPercentage
        self.threadCount = threadCount
        self.userTimeNs = userTimeNs
        self.systemTimeNs = systemTimeNs
        self.residentBytes = residentBytes
        self.virtualBytes = virtualBytes
        self.openFileDescriptorsCount = openFileDescriptorsCount
        self.startTime = startTime
        self.contextSwitches = contextSwitches
        self.faults = faults
        self.pageins = pageins
        self.cowFaults = cowFaults
        self.messagesSent = messagesSent
        self.messagesReceived = messagesReceived
        self.machSyscalls = machSyscalls
        self.unixSyscalls = unixSyscalls
        self.diskReadBytesPerSecond = diskReadBytesPerSecond
        self.diskWriteBytesPerSecond = diskWriteBytesPerSecond
        self.totalDiskReadBytes = totalDiskReadBytes
        self.totalDiskWriteBytes = totalDiskWriteBytes
    }

    // Computed formatters
    public var uptime: TimeInterval? {
        startTime.map { Date().timeIntervalSince($0) }
    }

    public var formattedUptime: String {
        guard let uptime else { return "—" }
        let totalSeconds = Int(uptime)
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    public var formattedStartTime: String {
        guard let startTime else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: startTime)
    }

    public var formattedVirtualMemory: String { Formatters.formatBytes(virtualBytes) }
    public var formattedResidentMemory: String { Formatters.formatBytes(residentBytes) }
    public var formattedDiskReadSpeed: String { Formatters.formatSpeed(diskReadBytesPerSecond) }
    public var formattedDiskWriteSpeed: String { Formatters.formatSpeed(diskWriteBytesPerSecond) }
    public var formattedTotalDiskRead: String { Formatters.formatBytes(totalDiskReadBytes) }
    public var formattedTotalDiskWrite: String { Formatters.formatBytes(totalDiskWriteBytes) }

    public var formattedDiagnosticsSummary: String {
        """
        Process: \(name) (PID: \(id))
        Parent PID: \(ppid)
        User: \(ownerUser)
        Architecture: \(architecture)
        Status: \(isSuspended ? "Suspended (Paused)" : "Running")
        Protected: \(isProtected ? "Yes" : "No")
        CPU Usage: \(String(format: "%.1f%%", cpuPercentage))
        Threads: \(threadCount)
        Resident Memory: \(formattedResidentMemory)
        Virtual Memory: \(formattedVirtualMemory)
        Open File Descriptors: \(openFileDescriptorsCount.map { "\($0)" } ?? "N/A")
        Launch Time: \(formattedStartTime)
        Uptime: \(formattedUptime)
        Context Switches: \(contextSwitches)
        Page Faults: \(faults) (Page-ins: \(pageins), COW: \(cowFaults))
        Disk Read Speed: \(formattedDiskReadSpeed) (Total: \(formattedTotalDiskRead))
        Disk Write Speed: \(formattedDiskWriteSpeed) (Total: \(formattedTotalDiskWrite))
        Executable: \(executablePath ?? "Unknown")
        """
    }
}
