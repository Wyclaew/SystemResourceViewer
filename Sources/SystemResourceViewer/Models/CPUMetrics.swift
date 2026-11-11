import Foundation

/// Core classification on Apple Silicon and hybrid CPU architectures.
public enum CoreType: String, Sendable, CaseIterable {
    case performance = "Performance"
    case efficiency = "Efficiency"

    public var shortLabel: String {
        switch self {
        case .performance: return "P"
        case .efficiency: return "E"
        }
    }
}

/// Real-time metrics for an individual logical or physical processor core.
public struct CoreUsage: Identifiable, Sendable {
    public let id: Int
    public let coreIndex: Int
    public let type: CoreType
    public let totalUsage: Double
    public let userUsage: Double
    public let systemUsage: Double
    public let idleUsage: Double

    public init(
        coreIndex: Int,
        type: CoreType,
        totalUsage: Double,
        userUsage: Double,
        systemUsage: Double,
        idleUsage: Double
    ) {
        self.id = coreIndex
        self.coreIndex = coreIndex
        self.type = type
        self.totalUsage = totalUsage
        self.userUsage = userUsage
        self.systemUsage = systemUsage
        self.idleUsage = idleUsage
    }
}

/// Comprehensive CPU telemetry metrics.
public struct CPUMetrics: Sendable {
    public let totalUsage: Double
    public let userPercentage: Double
    public let systemPercentage: Double
    public let idlePercentage: Double
    public let pCoreAverageUsage: Double
    public let eCoreAverageUsage: Double
    public let coreUsages: [CoreUsage]
    public let topProcesses: [ProcessItem]
    public let pCoreCount: Int
    public let eCoreCount: Int

    public init(
        totalUsage: Double = 0.0,
        userPercentage: Double = 0.0,
        systemPercentage: Double = 0.0,
        idlePercentage: Double = 100.0,
        pCoreAverageUsage: Double = 0.0,
        eCoreAverageUsage: Double = 0.0,
        coreUsages: [CoreUsage] = [],
        topProcesses: [ProcessItem] = [],
        pCoreCount: Int = 0,
        eCoreCount: Int = 0
    ) {
        self.totalUsage = totalUsage
        self.userPercentage = userPercentage
        self.systemPercentage = systemPercentage
        self.idlePercentage = idlePercentage
        self.pCoreAverageUsage = pCoreAverageUsage
        self.eCoreAverageUsage = eCoreAverageUsage
        self.coreUsages = coreUsages
        self.topProcesses = topProcesses
        self.pCoreCount = pCoreCount
        self.eCoreCount = eCoreCount
    }

    public static let empty = CPUMetrics()
}
