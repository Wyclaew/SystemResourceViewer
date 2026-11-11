import Foundation

/// Actor-isolated telemetry service monitoring physical and virtual memory allocation.
public actor MemoryMonitorService {

    public init() {}

    /// Polls Darwin kernel VM statistics, swap file metrics, and kernel pressure level.
    public func pollMemoryMetrics(topProcesses: [ProcessItem] = []) -> MemoryMetrics {
        guard let snapshot = DarwinMachBridge.fetchVMStatistics() else {
            return .empty
        }

        return MemoryMetrics(
            totalBytes: snapshot.totalPhysicalBytes,
            appMemoryBytes: snapshot.appBytes,
            wiredBytes: snapshot.wiredBytes,
            compressedBytes: snapshot.compressedBytes,
            cachedBytes: snapshot.cachedBytes,
            freeBytes: snapshot.freeBytes,
            swapUsedBytes: snapshot.swapUsedBytes,
            swapTotalBytes: snapshot.swapTotalBytes,
            pressureLevel: snapshot.pressureLevel,
            topProcesses: topProcesses
        )
    }
}
