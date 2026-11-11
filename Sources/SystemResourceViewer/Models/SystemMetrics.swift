import Foundation

/// Unified system telemetry snapshot across all monitored subsystems.
public struct SystemMetrics: Sendable {
    public let timestamp: Date
    public let cpu: CPUMetrics
    public let gpu: GPUMetrics
    public let memory: MemoryMetrics
    public let disk: DiskMetrics
    public let network: NetworkMetrics
    public let power: PowerMetrics
    public let thermal: ThermalMetrics
    public let processes: [ProcessItem]

    public init(
        timestamp: Date = Date(),
        cpu: CPUMetrics = .empty,
        gpu: GPUMetrics = .empty,
        memory: MemoryMetrics = .empty,
        disk: DiskMetrics = .empty,
        network: NetworkMetrics = .empty,
        power: PowerMetrics = .empty,
        thermal: ThermalMetrics = .empty,
        processes: [ProcessItem] = []
    ) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.gpu = gpu
        self.memory = memory
        self.disk = disk
        self.network = network
        self.power = power
        self.thermal = thermal
        self.processes = processes
    }

    public static let empty = SystemMetrics()
}
