import Foundation
import IOKit

/// Actor-isolated telemetry service monitoring disk storage I/O and Apple power/thermal subsystems.
public actor DiskAndPowerService {
    private var previousDiskSample: (read: UInt64, write: UInt64, time: Date)?

    public init() {}

    /// Polls both disk storage metrics and hardware battery/thermal telemetry.
    public func pollDiskAndPower() -> (disk: DiskMetrics, power: PowerMetrics) {
        let disk = pollDiskMetrics()
        let power = pollPowerMetrics()
        return (disk, power)
    }

    private func pollDiskMetrics() -> DiskMetrics {
        // Storage capacity for root volume
        var totalBytes: UInt64 = 0
        var freeBytes: UInt64 = 0
        var volumeName = "Macintosh HD"

        let fileURL = URL(fileURLWithPath: "/")
        do {
            let values = try fileURL.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeLocalizedNameKey
            ])
            totalBytes = UInt64(values.volumeTotalCapacity ?? 0)
            freeBytes = UInt64(values.volumeAvailableCapacity ?? 0)
            if let name = values.volumeLocalizedName, !name.isEmpty {
                volumeName = name
            }
        } catch {
            // Fallback to POSIX statfs if resourceValues encounters permission sandbox boundaries
            var stat = statfs()
            if statfs("/", &stat) == 0 {
                let blockSize = UInt64(stat.f_bsize)
                totalBytes = UInt64(stat.f_blocks) * blockSize
                freeBytes = UInt64(stat.f_bavail) * blockSize
            }
        }

        // Real-time disk I/O throughput via IOKit
        var readSpeed = 0.0
        var writeSpeed = 0.0
        let now = Date()

        if let currentIO = IOKitBridge.fetchCumulativeDiskIOBytes() {
            if let prev = previousDiskSample {
                let dt = now.timeIntervalSince(prev.time)
                if dt > 10.0 {
                    // System woke from sleep or clock jumped: reset baseline
                    previousDiskSample = (read: currentIO.readBytes, write: currentIO.writeBytes, time: now)
                    readSpeed = 0.0
                    writeSpeed = 0.0
                } else if dt > 0.05 {
                    let dRead = currentIO.readBytes >= prev.read ? currentIO.readBytes - prev.read : 0
                    let dWrite = currentIO.writeBytes >= prev.write ? currentIO.writeBytes - prev.write : 0
                    readSpeed = Double(dRead) / dt
                    writeSpeed = Double(dWrite) / dt
                }
            }
            previousDiskSample = (read: currentIO.readBytes, write: currentIO.writeBytes, time: now)
        }

        return DiskMetrics(
            volumeName: volumeName,
            totalBytes: totalBytes,
            freeBytes: freeBytes,
            readBytesPerSecond: readSpeed,
            writeBytesPerSecond: writeSpeed
        )
    }

    private func pollPowerMetrics() -> PowerMetrics {
        let details = IOKitBridge.fetchBatteryTelemetry()
        let thermal = ProcessInfo.processInfo.thermalState

        return PowerMetrics(
            isBatteryInstalled: details.isPresent,
            batteryPercentage: details.currentCapacity,
            isCharging: details.isCharging,
            isPluggedIn: details.isPluggedIn,
            cycleCount: details.cycleCount,
            healthPercentage: details.healthPercentage,
            powerDrawWatts: details.powerDrawWatts,
            timeRemainingMinutes: details.timeRemainingMinutes,
            thermalState: thermal
        )
    }
}
