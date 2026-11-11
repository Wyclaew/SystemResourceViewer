import Foundation

/// Disk capacity and real-time I/O storage telemetry.
public struct DiskMetrics: Sendable {
    public let volumeName: String
    public let totalBytes: UInt64
    public let freeBytes: UInt64
    public let readBytesPerSecond: Double
    public let writeBytesPerSecond: Double

    public init(
        volumeName: String = "Macintosh HD",
        totalBytes: UInt64 = 0,
        freeBytes: UInt64 = 0,
        readBytesPerSecond: Double = 0.0,
        writeBytesPerSecond: Double = 0.0
    ) {
        self.volumeName = volumeName
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.readBytesPerSecond = readBytesPerSecond
        self.writeBytesPerSecond = writeBytesPerSecond
    }

    public var usedBytes: UInt64 {
        totalBytes > freeBytes ? totalBytes - freeBytes : 0
    }

    public var usedPercentage: Double {
        guard totalBytes > 0 else { return 0.0 }
        return min(100.0, max(0.0, (Double(usedBytes) / Double(totalBytes)) * 100.0))
    }

    public var readMegaBytesPerSecond: Double {
        readBytesPerSecond / (1024 * 1024)
    }

    public var writeMegaBytesPerSecond: Double {
        writeBytesPerSecond / (1024 * 1024)
    }

    public static let empty = DiskMetrics()
}
