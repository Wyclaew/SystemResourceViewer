import Foundation

/// Comprehensive hardware and system profile specifications.
public struct HardwareProfile: Sendable, Equatable {
    public let modelIdentifier: String
    public let marketingModelName: String
    public let cpuBrand: String
    public let totalCores: Int
    public let performanceCores: Int
    public let efficiencyCores: Int
    public let totalMemoryBytes: UInt64
    public let osVersionString: String
    public let osBuildVersion: String
    public let kernelRelease: String
    public let bootTime: Date
    public let uptimeSeconds: TimeInterval

    public init(
        modelIdentifier: String,
        marketingModelName: String,
        cpuBrand: String,
        totalCores: Int,
        performanceCores: Int,
        efficiencyCores: Int,
        totalMemoryBytes: UInt64,
        osVersionString: String,
        osBuildVersion: String,
        kernelRelease: String,
        bootTime: Date,
        uptimeSeconds: TimeInterval
    ) {
        self.modelIdentifier = modelIdentifier
        self.marketingModelName = marketingModelName
        self.cpuBrand = cpuBrand
        self.totalCores = totalCores
        self.performanceCores = performanceCores
        self.efficiencyCores = efficiencyCores
        self.totalMemoryBytes = totalMemoryBytes
        self.osVersionString = osVersionString
        self.osBuildVersion = osBuildVersion
        self.kernelRelease = kernelRelease
        self.bootTime = bootTime
        self.uptimeSeconds = uptimeSeconds
    }

    /// Formats a clean Markdown system profile report for clipboard sharing.
    public func generateReport() -> String {
        """
        # System Hardware & OS Profile
        - **Hardware Model**: \(marketingModelName) (\(modelIdentifier))
        - **Processor**: \(cpuBrand)
        - **Core Architecture**: \(totalCores) Cores (\(performanceCores) Performance + \(efficiencyCores) Efficiency)
        - **Total Memory**: \(Formatters.formatBytes(totalMemoryBytes))
        - **macOS Version**: \(osVersionString) (Build \(osBuildVersion))
        - **Kernel**: \(kernelRelease)
        - **Boot Time**: \(bootTime.formatted(date: .abbreviated, time: .standard))
        - **System Uptime**: \(Formatters.formatUptime(uptimeSeconds))
        """
    }

    public static let fallback = HardwareProfile(
        modelIdentifier: "Mac",
        marketingModelName: "Mac",
        cpuBrand: "Apple Silicon",
        totalCores: 8,
        performanceCores: 4,
        efficiencyCores: 4,
        totalMemoryBytes: 16 * 1024 * 1024 * 1024,
        osVersionString: "macOS",
        osBuildVersion: "Unknown",
        kernelRelease: "Darwin",
        bootTime: Date(),
        uptimeSeconds: 0
    )
}
