import Foundation

/// Actor-isolated telemetry service monitoring CPU load and Apple Silicon core topology.
public actor CPUMonitorService {
    private let topology: DarwinMachBridge.CPUTopology
    private var previousTicks: [DarwinMachBridge.CPUTicks]?

    public init() {
        self.topology = DarwinMachBridge.fetchCPUTopology()
    }

    /// Polls instantaneous CPU telemetry and calculates delta load since last poll.
    public func pollCPUMetrics(topProcesses: [ProcessItem] = []) -> CPUMetrics {
        guard let currentTicks = DarwinMachBridge.fetchProcessorTicks() else {
            return .empty
        }

        guard let prev = previousTicks, prev.count == currentTicks.count else {
            // First sample: store baseline and return initial idle state
            self.previousTicks = currentTicks
            return CPUMetrics(
                totalUsage: 0.0,
                userPercentage: 0.0,
                systemPercentage: 0.0,
                idlePercentage: 100.0,
                pCoreAverageUsage: 0.0,
                eCoreAverageUsage: 0.0,
                coreUsages: currentTicks.enumerated().map { index, _ in
                    let coreType = determineCoreType(for: index)
                    return CoreUsage(
                        coreIndex: index,
                        type: coreType,
                        totalUsage: 0.0,
                        userUsage: 0.0,
                        systemUsage: 0.0,
                        idleUsage: 100.0
                    )
                },
                topProcesses: topProcesses,
                pCoreCount: topology.performanceCores,
                eCoreCount: topology.efficiencyCores
            )
        }

        self.previousTicks = currentTicks

        var coreUsages: [CoreUsage] = []
        coreUsages.reserveCapacity(currentTicks.count)

        var totalDeltaUser: UInt64 = 0
        var totalDeltaSystem: UInt64 = 0
        var totalDeltaIdle: UInt64 = 0
        var totalDeltaNice: UInt64 = 0

        var pCoreUsageSum = 0.0
        var pCoreCount = 0
        var eCoreUsageSum = 0.0
        var eCoreCount = 0

        for i in 0..<currentTicks.count {
            let cur = currentTicks[i]
            let old = prev[i]

            let dUser = cur.user >= old.user ? cur.user - old.user : 0
            let dSystem = cur.system >= old.system ? cur.system - old.system : 0
            let dIdle = cur.idle >= old.idle ? cur.idle - old.idle : 0
            let dNice = cur.nice >= old.nice ? cur.nice - old.nice : 0

            let dTotal = dUser + dSystem + dIdle + dNice

            totalDeltaUser += dUser
            totalDeltaSystem += dSystem
            totalDeltaIdle += dIdle
            totalDeltaNice += dNice

            let coreType = determineCoreType(for: i)
            let coreUsagePercent: Double
            let coreUserPercent: Double
            let coreSystemPercent: Double
            let coreIdlePercent: Double

            if dTotal > 0 {
                let busy = dUser + dSystem + dNice
                coreUsagePercent = min(100.0, max(0.0, (Double(busy) / Double(dTotal)) * 100.0))
                coreUserPercent = min(100.0, max(0.0, (Double(dUser + dNice) / Double(dTotal)) * 100.0))
                coreSystemPercent = min(100.0, max(0.0, (Double(dSystem) / Double(dTotal)) * 100.0))
                coreIdlePercent = min(100.0, max(0.0, (Double(dIdle) / Double(dTotal)) * 100.0))
            } else {
                coreUsagePercent = 0.0
                coreUserPercent = 0.0
                coreSystemPercent = 0.0
                coreIdlePercent = 100.0
            }

            if coreType == .performance {
                pCoreUsageSum += coreUsagePercent
                pCoreCount += 1
            } else {
                eCoreUsageSum += coreUsagePercent
                eCoreCount += 1
            }

            coreUsages.append(CoreUsage(
                coreIndex: i,
                type: coreType,
                totalUsage: coreUsagePercent,
                userUsage: coreUserPercent,
                systemUsage: coreSystemPercent,
                idleUsage: coreIdlePercent
            ))
        }

        let grandTotal = totalDeltaUser + totalDeltaSystem + totalDeltaIdle + totalDeltaNice
        let overallUsage: Double
        let userPercent: Double
        let systemPercent: Double
        let idlePercent: Double

        if grandTotal > 0 {
            let busy = totalDeltaUser + totalDeltaSystem + totalDeltaNice
            overallUsage = min(100.0, max(0.0, (Double(busy) / Double(grandTotal)) * 100.0))
            userPercent = min(100.0, max(0.0, (Double(totalDeltaUser + totalDeltaNice) / Double(grandTotal)) * 100.0))
            systemPercent = min(100.0, max(0.0, (Double(totalDeltaSystem) / Double(grandTotal)) * 100.0))
            idlePercent = min(100.0, max(0.0, (Double(totalDeltaIdle) / Double(grandTotal)) * 100.0))
        } else {
            overallUsage = 0.0
            userPercent = 0.0
            systemPercent = 0.0
            idlePercent = 100.0
        }

        let avgPCore = pCoreCount > 0 ? (pCoreUsageSum / Double(pCoreCount)) : 0.0
        let avgECore = eCoreCount > 0 ? (eCoreUsageSum / Double(eCoreCount)) : 0.0

        return CPUMetrics(
            totalUsage: overallUsage,
            userPercentage: userPercent,
            systemPercentage: systemPercent,
            idlePercentage: idlePercent,
            pCoreAverageUsage: avgPCore,
            eCoreAverageUsage: avgECore,
            coreUsages: coreUsages,
            topProcesses: topProcesses,
            pCoreCount: topology.performanceCores,
            eCoreCount: topology.efficiencyCores
        )
    }

    /// On Apple Silicon Darwin kernels, E-cores are assigned indices [0 ..< eCores]
    /// and P-cores are assigned [eCores ..< totalCores].
    private func determineCoreType(for coreIndex: Int) -> CoreType {
        if topology.efficiencyCores > 0 {
            return coreIndex < topology.efficiencyCores ? .efficiency : .performance
        }
        return .performance
    }
}
