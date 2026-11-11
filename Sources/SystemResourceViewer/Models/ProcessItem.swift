import AppKit
import Foundation

/// Categories for filtering active processes.
public enum ProcessCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case apps = "Apps"
    case daemons = "Daemons"
    case system = "System"
    case highLoad = "High Load"

    public var id: String { rawValue }
}

/// Represents an active macOS process with parent-child hierarchy support (Task Manager tree style).
public struct ProcessItem: Identifiable, Sendable, Hashable {
    public let id: pid_t
    public let ppid: pid_t
    public let name: String
    public let bundleIdentifier: String?
    public let cpuPercentage: Double
    public let memoryBytes: UInt64
    public let icon: NSImage?
    public var children: [ProcessItem]

    // Extended Metadata
    public let architecture: String
    public let threadCount: Int
    public let ownerUser: String
    public let executablePath: String?
    public let category: ProcessCategory

    public init(
        id: pid_t,
        ppid: pid_t = 0,
        name: String,
        bundleIdentifier: String? = nil,
        cpuPercentage: Double,
        memoryBytes: UInt64,
        icon: NSImage? = nil,
        children: [ProcessItem] = [],
        architecture: String = "Apple Silicon",
        threadCount: Int = 1,
        ownerUser: String = "root",
        executablePath: String? = nil,
        category: ProcessCategory = .all
    ) {
        self.id = id
        self.ppid = ppid
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.cpuPercentage = cpuPercentage
        self.memoryBytes = memoryBytes
        self.icon = icon
        self.children = children
        self.architecture = architecture
        self.threadCount = threadCount
        self.ownerUser = ownerUser
        self.executablePath = executablePath
        self.category = category
    }

    /// True if running under Rosetta 2 translation.
    public var isRosetta: Bool {
        architecture == "Rosetta 2"
    }

    /// True if this process has one or more nested child processes.
    public var hasChildren: Bool {
        !children.isEmpty
    }

    /// Aggregate total CPU consumption across this process and all nested child processes.
    public var totalCPU: Double {
        cpuPercentage + children.reduce(0.0) { $0 + $1.totalCPU }
    }

    /// Aggregate total memory consumption across this process and all nested child processes.
    public var totalMemory: UInt64 {
        memoryBytes + children.reduce(0) { $0 + $1.totalMemory }
    }

    public var formattedCPU: String {
        String(format: "%.1f%%", cpuPercentage)
    }

    public var formattedTotalCPU: String {
        String(format: "%.1f%%", totalCPU)
    }

    public var formattedMemory: String {
        formatBytes(memoryBytes)
    }

    public var formattedTotalMemory: String {
        formatBytes(totalMemory)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1024 {
            return String(format: "%.2f GB", mb / 1024)
        } else {
            return String(format: "%.0f MB", mb)
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: ProcessItem, rhs: ProcessItem) -> Bool {
        lhs.id == rhs.id
    }
}
