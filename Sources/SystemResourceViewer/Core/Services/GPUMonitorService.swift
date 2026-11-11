import Foundation

/// Actor-isolated telemetry service monitoring GPU load, engine utilization, and VRAM.
public actor GPUMonitorService {
    private var cachedModelName: String?
    private var cachedCoreCount: Int?

    public init() {}

    /// Polls instantaneous GPU telemetry metrics.
    /// Reuses cached model name and core count to minimize IOKit registry overhead.
    public func pollGPUMetrics() -> GPUMetrics {
        guard let snapshot = IOKitBridge.fetchGPUHardwareDetails() else {
            return .empty
        }

        // Cache static hardware properties on first valid poll
        let model = cachedModelName ?? snapshot.modelName
        let cores = cachedCoreCount ?? snapshot.coreCount

        if cachedModelName == nil && !snapshot.modelName.isEmpty {
            self.cachedModelName = snapshot.modelName
        }
        if cachedCoreCount == nil && snapshot.coreCount > 0 {
            self.cachedCoreCount = snapshot.coreCount
        }

        return GPUMetrics(
            deviceUtilization: snapshot.deviceUtilization,
            rendererUtilization: snapshot.rendererUtilization,
            tilerUtilization: snapshot.tilerUtilization,
            allocatedVRAMBytes: snapshot.allocatedVRAMBytes,
            inUseVRAMBytes: snapshot.inUseVRAMBytes,
            coreCount: cores,
            modelName: model,
            hasUnifiedMemory: snapshot.hasUnifiedMemory
        )
    }
}
