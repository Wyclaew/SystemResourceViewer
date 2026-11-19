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
    public let isSuspended: Bool
    public let diskReadBytesPerSecond: Double
    public let diskWriteBytesPerSecond: Double
    public let totalDiskReadBytes: UInt64
    public let totalDiskWriteBytes: UInt64

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
        category: ProcessCategory = .all,
        isSuspended: Bool = false,
        diskReadBytesPerSecond: Double = 0.0,
        diskWriteBytesPerSecond: Double = 0.0,
        totalDiskReadBytes: UInt64 = 0,
        totalDiskWriteBytes: UInt64 = 0
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
        self.isSuspended = isSuspended
        self.diskReadBytesPerSecond = diskReadBytesPerSecond
        self.diskWriteBytesPerSecond = diskWriteBytesPerSecond
        self.totalDiskReadBytes = totalDiskReadBytes
        self.totalDiskWriteBytes = totalDiskWriteBytes
    }

    /// True if running under Rosetta 2 translation.
    public var isRosetta: Bool {
        architecture == "Rosetta 2"
    }

    /// True if this process is protected from termination by ProcessGuard.
    public var isProtected: Bool {
        ProcessGuard.isProtected(pid: id, name: name, bundleIdentifier: bundleIdentifier, path: executablePath)
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

    public var diskBytesPerSecond: Double {
        diskReadBytesPerSecond + diskWriteBytesPerSecond
    }

    public var totalDiskBytesPerSecond: Double {
        diskBytesPerSecond + children.reduce(0.0) { $0 + $1.totalDiskBytesPerSecond }
    }

    public var formattedDiskIO: String {
        Formatters.formatSpeed(diskBytesPerSecond)
    }

    public var formattedTotalDiskIO: String {
        Formatters.formatSpeed(totalDiskBytesPerSecond)
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
        lhs.id == rhs.id &&
        lhs.cpuPercentage == rhs.cpuPercentage &&
        lhs.memoryBytes == rhs.memoryBytes &&
        lhs.architecture == rhs.architecture &&
        lhs.category == rhs.category &&
        lhs.isSuspended == rhs.isSuspended &&
        lhs.children == rhs.children
    }

    // MARK: - Thread-Safe Path-Based Icon Cache

    /// Thread-safe icon cache keyed by persistent executable path to avoid redundant AppKit icon queries.
    public final class IconCache: @unchecked Sendable {
        public static let shared = IconCache()
        private var storage: [String: NSImage] = [:]
        private let lock = NSLock()

        public init() {}

        public func icon(forPath path: String) -> NSImage? {
            lock.lock()
            defer { lock.unlock() }
            return storage[path]
        }

        public func setIcon(_ icon: NSImage, forPath path: String) {
            lock.lock()
            defer { lock.unlock() }
            storage[path] = icon
        }

        public func clear() {
            lock.lock()
            defer { lock.unlock() }
            storage.removeAll()
        }

        public var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return storage.count
        }
    }
}
