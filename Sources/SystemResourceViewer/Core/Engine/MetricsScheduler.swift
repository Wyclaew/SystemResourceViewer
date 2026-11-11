import Foundation

/// Centralized metrics scheduler orchestrating actor-isolated telemetry workers.
public actor MetricsScheduler {
    public enum PollingMode: Sendable {
        /// Popover or full window is visible: sample all metrics including per-core and top processes.
        case full
        /// Popover and window are hidden: sample only lightweight stats for Menu Bar text updates.
        case minimal
    }

    private let cpuService = CPUMonitorService()
    private let memoryService = MemoryMonitorService()
    private let processService = ProcessMonitorService()
    private let diskAndPowerService = DiskAndPowerService()
    private let networkService = NetworkMonitorService()
    private let gpuService = GPUMonitorService()
    private let thermalService = ThermalMonitorService()

    private var currentInterval: TimeInterval = 2.0
    private var currentMode: PollingMode = .full
    private var lastThermalMetrics: ThermalMetrics = .empty
    private var pollingTask: Task<Void, Never>?
    private var streamContinuation: AsyncStream<SystemMetrics>.Continuation?

    public init(interval: TimeInterval = 2.0) {
        self.currentInterval = interval
    }

    /// Sets the polling frequency (1s, 2s, 5s).
    public func setRefreshInterval(_ interval: TimeInterval) {
        guard self.currentInterval != interval else { return }
        self.currentInterval = interval
        restartPolling()
    }

    /// Toggles between full diagnostics and ultra-low-power minimal menu bar polling.
    public func setPollingMode(_ mode: PollingMode) {
        guard self.currentMode != mode else { return }
        self.currentMode = mode
    }

    /// Returns an asynchronous stream emitting live snapshots of SystemMetrics.
    public func metricsStream() -> AsyncStream<SystemMetrics> {
        AsyncStream { [weak self] continuation in
            Task { [weak self] in
                guard let self else { return }
                await self.registerContinuation(continuation)
            }
        }
    }

    private func registerContinuation(_ continuation: AsyncStream<SystemMetrics>.Continuation) {
        self.streamContinuation = continuation
        continuation.onTermination = { [weak self] _ in
            Task { [weak self] in
                await self?.stop()
            }
        }
        startPolling()
    }

    /// Starts or restarts the polling loop.
    public func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let metrics = await self.sampleMetrics()
                await self.yieldMetrics(metrics)

                let interval = await self.currentInterval
                let nanoseconds = UInt64(interval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
        }
    }

    private func restartPolling() {
        startPolling()
    }

    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func yieldMetrics(_ metrics: SystemMetrics) {
        streamContinuation?.yield(metrics)
    }

    /// Samples hardware metrics based on the active polling mode.
    private func sampleMetrics() async -> SystemMetrics {
        let topology = DarwinMachBridge.fetchCPUTopology()

        switch currentMode {
        case .full:
            // Comprehensive diagnostics
            // First get CPU metrics (needed for hardware total CPU percentage)
            let cpu = await cpuService.pollCPUMetrics(topProcesses: [])
            
            async let gpuTask = gpuService.pollGPUMetrics()
            async let thermalTask = thermalService.pollThermalMetrics()
            async let procTask = processService.pollProcesses(
                coreCount: topology.totalCores,
                totalHardwareCPU: cpu.totalUsage
            )
            async let diskPowerTask = diskAndPowerService.pollDiskAndPower()
            async let netTask = networkService.pollNetworkMetrics()

            let gpu = await gpuTask
            let thermal = await thermalTask
            self.lastThermalMetrics = thermal
            let procResult = await procTask
            let (disk, power) = await diskPowerTask
            let net = await netTask

            // Re-create CPU metrics with actual top processes
            let cpuWithProcs = CPUMetrics(
                totalUsage: cpu.totalUsage,
                userPercentage: cpu.userPercentage,
                systemPercentage: cpu.systemPercentage,
                idlePercentage: cpu.idlePercentage,
                pCoreAverageUsage: cpu.pCoreAverageUsage,
                eCoreAverageUsage: cpu.eCoreAverageUsage,
                coreUsages: cpu.coreUsages,
                topProcesses: procResult.topCPU,
                pCoreCount: cpu.pCoreCount,
                eCoreCount: cpu.eCoreCount
            )
            let mem = await memoryService.pollMemoryMetrics(topProcesses: procResult.topMemory)

            return SystemMetrics(
                timestamp: Date(),
                cpu: cpuWithProcs,
                gpu: gpu,
                memory: mem,
                disk: disk,
                network: net,
                power: power,
                thermal: thermal,
                processes: procResult.allProcesses
            )

        case .minimal:
            // Ultra-lightweight background polling: bypass heavy process table and thermal inspections
            async let cpuTask = cpuService.pollCPUMetrics(topProcesses: [])
            async let gpuTask = gpuService.pollGPUMetrics()
            async let memTask = memoryService.pollMemoryMetrics(topProcesses: [])
            async let netTask = networkService.pollNetworkMetrics()
            async let diskPowerTask = diskAndPowerService.pollDiskAndPower()

            let cpu = await cpuTask
            let gpu = await gpuTask
            let mem = await memTask
            let net = await netTask
            let (disk, power) = await diskPowerTask

            return SystemMetrics(
                timestamp: Date(),
                cpu: cpu,
                gpu: gpu,
                memory: mem,
                disk: disk,
                network: net,
                power: power,
                thermal: lastThermalMetrics
            )
        }
    }
}
