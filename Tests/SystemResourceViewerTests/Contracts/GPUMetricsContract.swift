import Foundation

/// Contract definition for GPU Telemetry matching PROJECT.md § Interface Contracts
public struct GPUMetricsContract: Sendable, Equatable {
    public let deviceUtilization: Double
    public let rendererUtilization: Double
    public let tilerUtilization: Double
    public let allocatedVRAMBytes: UInt64
    public let inUseVRAMBytes: UInt64
    public let coreCount: Int
    public let modelName: String

    public init(
        deviceUtilization: Double = 0.0,
        rendererUtilization: Double = 0.0,
        tilerUtilization: Double = 0.0,
        allocatedVRAMBytes: UInt64 = 0,
        inUseVRAMBytes: UInt64 = 0,
        coreCount: Int = 0,
        modelName: String = "Apple Silicon GPU"
    ) {
        self.deviceUtilization = deviceUtilization
        self.rendererUtilization = rendererUtilization
        self.tilerUtilization = tilerUtilization
        self.allocatedVRAMBytes = allocatedVRAMBytes
        self.inUseVRAMBytes = inUseVRAMBytes
        self.coreCount = coreCount
        self.modelName = modelName
    }

    public static let empty = GPUMetricsContract()

    public var clampedDeviceUtilization: Double {
        min(100.0, max(0.0, deviceUtilization))
    }

    public var vramUsagePercentage: Double {
        guard allocatedVRAMBytes > 0 else { return 0.0 }
        return min(100.0, max(0.0, (Double(inUseVRAMBytes) / Double(allocatedVRAMBytes)) * 100.0))
    }
}
