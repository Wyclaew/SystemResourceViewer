import Foundation

/// Comprehensive GPU telemetry snapshot covering hardware model, engine utilization, and VRAM.
public struct GPUMetrics: Sendable, Equatable {
    public let modelName: String
    public let coreCount: Int
    public let deviceUtilization: Double       // 0.0 ... 100.0%
    public let rendererUtilization: Double     // 0.0 ... 100.0%
    public let tilerUtilization: Double        // 0.0 ... 100.0%
    public let allocatedVRAMBytes: UInt64
    public let inUseVRAMBytes: UInt64
    public let hasUnifiedMemory: Bool

    public init(
        deviceUtilization: Double = 0.0,
        rendererUtilization: Double = 0.0,
        tilerUtilization: Double = 0.0,
        allocatedVRAMBytes: UInt64 = 0,
        inUseVRAMBytes: UInt64 = 0,
        coreCount: Int = 0,
        modelName: String = "Apple Silicon GPU",
        hasUnifiedMemory: Bool = true
    ) {
        self.deviceUtilization = deviceUtilization
        self.rendererUtilization = rendererUtilization
        self.tilerUtilization = tilerUtilization
        self.allocatedVRAMBytes = allocatedVRAMBytes
        self.inUseVRAMBytes = inUseVRAMBytes
        self.coreCount = coreCount
        self.modelName = modelName
        self.hasUnifiedMemory = hasUnifiedMemory
    }

    /// Calculated VRAM utilization percentage (0.0 ... 100.0%).
    public var vramUsagePercentage: Double {
        guard allocatedVRAMBytes > 0 else { return 0.0 }
        let pct = (Double(inUseVRAMBytes) / Double(allocatedVRAMBytes)) * 100.0
        return min(100.0, max(0.0, pct))
    }

    /// Clamped device utilization between 0.0% and 100.0%
    public var clampedDeviceUtilization: Double {
        min(100.0, max(0.0, deviceUtilization))
    }

    /// Default empty placeholder metric instance.
    public static let empty = GPUMetrics()
}
