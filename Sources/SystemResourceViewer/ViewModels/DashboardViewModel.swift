import AppKit
import Combine
import Foundation

/// MainActor-isolated ViewModel managing UI state, live history buffers, and scheduler mode.
@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public private(set) var metrics: SystemMetrics = .empty
    @Published public var refreshInterval: TimeInterval = 2.0 {
        didSet {
            Task {
                await scheduler.setRefreshInterval(refreshInterval)
            }
        }
    }

    @Published public var isPopoverOpen: Bool = false {
        didSet { updateSchedulerMode() }
    }

    @Published public var isDashboardWindowOpen: Bool = false {
        didSet { updateSchedulerMode() }
    }

    // Historical buffers (last 60 data points for Swift Charts sparklines)
    @Published public private(set) var cpuHistory: [Double] = Array(repeating: 0.0, count: 60)
    @Published public private(set) var gpuHistory: [Double] = Array(repeating: 0.0, count: 60)
    @Published public private(set) var memoryHistory: [Double] = Array(repeating: 0.0, count: 60)
    @Published public private(set) var socTemperatureHistory: [Double] = Array(repeating: 0.0, count: 60)
    @Published public private(set) var downloadSpeedHistory: [Double] = Array(repeating: 0.0, count: 60)
    @Published public private(set) var uploadSpeedHistory: [Double] = Array(repeating: 0.0, count: 60)
    @Published public private(set) var diskReadHistory: [Double] = Array(repeating: 0.0, count: 60)
    @Published public private(set) var diskWriteHistory: [Double] = Array(repeating: 0.0, count: 60)

    // Update Checker State
    @Published public var pendingUpdate: GitHubRelease? = nil
    @Published public var isCheckingForUpdates: Bool = false
    @Published public var showUpdateConfirmation: Bool = false

    // Easter Egg State Machine (Milestone 3)
    public let easterEggStateMachine: EasterEggStateMachine

    private let scheduler: MetricsScheduler
    private let updateCheckerService: UpdateCheckerService
    private var streamingTask: Task<Void, Never>?

    public init(
        interval: TimeInterval = 2.0,
        updateCheckerService: UpdateCheckerService = .shared,
        easterEggStateMachine: EasterEggStateMachine = EasterEggStateMachine()
    ) {
        self.refreshInterval = interval
        self.scheduler = MetricsScheduler(interval: interval)
        self.updateCheckerService = updateCheckerService
        self.easterEggStateMachine = easterEggStateMachine
        self.startObserving()
    }


    deinit {
        streamingTask?.cancel()
    }

    private func startObserving() {
        streamingTask?.cancel()
        streamingTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.scheduler.metricsStream()
            for await snapshot in stream {
                guard !Task.isCancelled else { break }
                self.handleNewMetrics(snapshot)
            }
        }
    }

    private func handleNewMetrics(_ snapshot: SystemMetrics) {
        self.metrics = snapshot

        // Append to 60-second fixed-capacity rolling buffers
        appendHistory(&cpuHistory, value: snapshot.cpu.totalUsage)
        appendHistory(&gpuHistory, value: snapshot.gpu.deviceUtilization)
        appendHistory(&memoryHistory, value: snapshot.memory.usedPercentage)
        appendHistory(&socTemperatureHistory, value: snapshot.thermal.socDieTemperature ?? 0.0)
        appendHistory(&downloadSpeedHistory, value: snapshot.network.downloadBytesPerSecond)
        appendHistory(&uploadSpeedHistory, value: snapshot.network.uploadBytesPerSecond)
        appendHistory(&diskReadHistory, value: snapshot.disk.readBytesPerSecond)
        appendHistory(&diskWriteHistory, value: snapshot.disk.writeBytesPerSecond)
    }

    public var thermalMetrics: ThermalMetrics {
        metrics.thermal
    }

    private func appendHistory(_ buffer: inout [Double], value: Double) {
        buffer.append(value)
        if buffer.count > 60 {
            buffer.removeFirst(buffer.count - 60)
        }
    }

    private func updateSchedulerMode() {
        let shouldRunFull = isPopoverOpen || isDashboardWindowOpen
        Task {
            await scheduler.setPollingMode(shouldRunFull ? .full : .minimal)
        }
    }

    // MARK: - Menu Bar Summary String

    public var menuBarTitle: String {
        let cpu = Int(round(metrics.cpu.totalUsage))
        let gpu = Int(round(metrics.gpu.deviceUtilization))
        let mem = Int(round(metrics.memory.usedPercentage))
        let rx = Formatters.formatSpeed(metrics.network.downloadBytesPerSecond)
        return "CPU \(cpu)%  GPU \(gpu)%  RAM \(mem)%  ↓ \(rx)"
    }

    // MARK: - Update Checker

    public func checkForUpdates(currentVersion: String? = nil) async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }

        let version = currentVersion ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
        let update = await updateCheckerService.checkForUpdates(currentVersion: version)
        self.pendingUpdate = update
        if update != nil {
            self.showUpdateConfirmation = true
        }
    }

    public func confirmUpdateAndOpenBrowser() {
        guard let release = pendingUpdate, let url = URL(string: release.htmlUrl) else {
            showUpdateConfirmation = false
            return
        }
        NSWorkspace.shared.open(url)
        showUpdateConfirmation = false
    }

    public func dismissUpdate() {
        pendingUpdate = nil
        showUpdateConfirmation = false
    }

    // MARK: - App Actions

    public func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
