import Foundation

/// Memory pressure classifications matching macOS Darwin kernel definitions.
public enum MemoryPressureLevel: String, Sendable {
    case normal = "Normal"
    case warning = "Warning"
    case critical = "Critical"

    public var systemSymbolName: String {
        switch self {
        case .normal: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }
}

/// Comprehensive Memory (RAM) telemetry metrics.
public struct MemoryMetrics: Sendable {
    public let totalBytes: UInt64
    public let appMemoryBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64
    public let cachedBytes: UInt64
    public let freeBytes: UInt64
    public let swapUsedBytes: UInt64
    public let swapTotalBytes: UInt64
    public let pressureLevel: MemoryPressureLevel
    public let topProcesses: [ProcessItem]

    public init(
        totalBytes: UInt64 = 0,
        appMemoryBytes: UInt64 = 0,
        wiredBytes: UInt64 = 0,
        compressedBytes: UInt64 = 0,
        cachedBytes: UInt64 = 0,
        freeBytes: UInt64 = 0,
        swapUsedBytes: UInt64 = 0,
        swapTotalBytes: UInt64 = 0,
        pressureLevel: MemoryPressureLevel = .normal,
        topProcesses: [ProcessItem] = []
    ) {
        self.totalBytes = totalBytes
        self.appMemoryBytes = appMemoryBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.cachedBytes = cachedBytes
        self.freeBytes = freeBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.pressureLevel = pressureLevel
        self.topProcesses = topProcesses
    }

    /// Total actively committed memory (App Memory + Wired + Compressed)
    public var usedBytes: UInt64 {
        appMemoryBytes + wiredBytes + compressedBytes
    }

    /// Percentage of total memory occupied by actively committed pages.
    public var usedPercentage: Double {
        guard totalBytes > 0 else { return 0.0 }
        return min(100.0, max(0.0, (Double(usedBytes) / Double(totalBytes)) * 100.0))
    }

    public static let empty = MemoryMetrics()
}
