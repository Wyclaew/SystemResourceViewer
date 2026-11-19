import AppKit
import Combine
import Foundation

/// MainActor-isolated ViewModel managing UI state, live history buffers, and scheduler mode.
@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public private(set) var metrics: SystemMetrics = .empty
    @Published public var refreshInterval: TimeInterval = 2.0 {
        didSet {
            Task { [weak self] in
                guard let scheduler = self?.scheduler, let interval = self?.refreshInterval else { return }
                await scheduler.setRefreshInterval(interval)
            }
        }
    }

    @Published public var isPopoverOpen: Bool = false {
        didSet { updateSchedulerMode() }
    }

    @Published public var isDashboardWindowOpen: Bool = false {
        didSet { updateSchedulerMode() }
    }

    @Published public var isWindowVisible: Bool = true {
        didSet { updateSchedulerMode() }
    }

    // Unified Multi-Tab Navigation State (Milestone 3)
    @Published public var selectedTab: DashboardTab = .processes

    // Historical buffers (last 60 data points for Swift Charts sparklines, backed by O(1) RingBuffer)
    @Published public private(set) var cpuHistory: RingBuffer<Double> = RingBuffer(capacity: 60, initialElement: 0.0)
    @Published public private(set) var gpuHistory: RingBuffer<Double> = RingBuffer(capacity: 60, initialElement: 0.0)
    @Published public private(set) var memoryHistory: RingBuffer<Double> = RingBuffer(capacity: 60, initialElement: 0.0)
    @Published public private(set) var socTemperatureHistory: RingBuffer<Double> = RingBuffer(capacity: 60, initialElement: 0.0)
    @Published public private(set) var downloadSpeedHistory: RingBuffer<Double> = RingBuffer(capacity: 60, initialElement: 0.0)
    @Published public private(set) var uploadSpeedHistory: RingBuffer<Double> = RingBuffer(capacity: 60, initialElement: 0.0)
    @Published public private(set) var diskReadHistory: RingBuffer<Double> = RingBuffer(capacity: 60, initialElement: 0.0)
    @Published public private(set) var diskWriteHistory: RingBuffer<Double> = RingBuffer(capacity: 60, initialElement: 0.0)

    // Extended 15-Minute Historical Buffers (capacity 900 for Multi-Timeline History Charts)
    @Published public private(set) var cpuHistory15m: RingBuffer<Double> = RingBuffer(capacity: 900, initialElement: 0.0)
    @Published public private(set) var gpuHistory15m: RingBuffer<Double> = RingBuffer(capacity: 900, initialElement: 0.0)
    @Published public private(set) var memoryHistory15m: RingBuffer<Double> = RingBuffer(capacity: 900, initialElement: 0.0)
    @Published public private(set) var socTemperatureHistory15m: RingBuffer<Double> = RingBuffer(capacity: 900, initialElement: 0.0)
    @Published public private(set) var downloadSpeedHistory15m: RingBuffer<Double> = RingBuffer(capacity: 900, initialElement: 0.0)
    @Published public private(set) var uploadSpeedHistory15m: RingBuffer<Double> = RingBuffer(capacity: 900, initialElement: 0.0)
    @Published public private(set) var diskReadHistory15m: RingBuffer<Double> = RingBuffer(capacity: 900, initialElement: 0.0)
    @Published public private(set) var diskWriteHistory15m: RingBuffer<Double> = RingBuffer(capacity: 900, initialElement: 0.0)

    @Published public var selectedHistoryRange: HistoryTimelineRange = .oneMinute

    // Process Inspection Modal State
    @Published public var inspectingProcess: ProcessItem? = nil

    // User Settings & Preferences
    @Published public var isSettingsOpen: Bool = false
    @Published public var userSettings: UserSettings {
        didSet {
            userSettings.save()
            if userSettings.refreshInterval != refreshInterval {
                refreshInterval = userSettings.refreshInterval
            }
            if userSettings.privacySettings != privacySettings {
                privacySettings = userSettings.privacySettings
            }
        }
    }

    // Hardware & System Profile
    @Published public private(set) var hardwareProfile: HardwareProfile = DarwinMachBridge.fetchHardwareProfile()

    // Intelligent Resource Threshold Alerts
    @Published public private(set) var activeAlerts: [SystemAlert] = []
    @Published public private(set) var alertHistory: [SystemAlert] = []
    private var alertLastFired: [AlertType: Date] = [:]

    // Background Process Filtering and Sorting State
    @Published public var searchText: String = "" {
        didSet { scheduleProcessFilter() }
    }
    @Published public var selectedCategory: ProcessCategory = .all {
        didSet { scheduleProcessFilter() }
    }
    @Published public var sortField: ProcessSortField = .cpu {
        didSet { scheduleProcessFilter() }
    }
    @Published public var sortAscending: Bool = false {
        didSet { scheduleProcessFilter() }
    }
    @Published public private(set) var filteredProcesses: [ProcessItem] = []

    // Update Checker State
    @Published public var pendingUpdate: GitHubRelease? = nil
    @Published public var isCheckingForUpdates: Bool = false
    @Published public var showUpdateConfirmation: Bool = false

    // Two-Step Process Termination Confirmation State
    @Published public var pendingTermination: ProcessTerminationRequest? = nil
    @Published public var showTerminationConfirmation: Bool = false
    @Published public var lastActionResultMessage: String? = nil

    // Privacy Settings & Controls
    @Published public var privacySettings: PrivacySettings = .defaultSettings {
        didSet {
            Task { [weak self] in
                guard let scheduler = self?.scheduler, let allowed = self?.privacySettings.allowExternalSocketProbe else { return }
                await scheduler.setAllowExternalSocketProbe(allowed)
            }
        }
    }

    // Easter Egg State Machine (Milestone 3)
    public let easterEggStateMachine: EasterEggStateMachine

    private let scheduler: MetricsScheduler
    private let updateCheckerService: UpdateCheckerService
    private var streamingTask: Task<Void, Never>?
    private var filterTask: Task<Void, Never>?

    public init(
        interval: TimeInterval? = nil,
        updateCheckerService: UpdateCheckerService = .shared,
        easterEggStateMachine: EasterEggStateMachine = EasterEggStateMachine(),
        userSettings: UserSettings = UserSettings.load()
    ) {
        self.userSettings = userSettings
        let activeInterval = interval ?? userSettings.refreshInterval
        self.refreshInterval = activeInterval
        self.scheduler = MetricsScheduler(interval: activeInterval)
        self.updateCheckerService = updateCheckerService
        self.easterEggStateMachine = easterEggStateMachine
        if let tab = DashboardTab(rawValue: userSettings.startupTab) {
            self.selectedTab = tab
        }
        if let range = HistoryTimelineRange(rawValue: userSettings.historyTimelineRange) {
            self.selectedHistoryRange = range
        }
        if self.privacySettings != userSettings.privacySettings {
            self.privacySettings = userSettings.privacySettings
        }
        self.hardwareProfile = DarwinMachBridge.fetchHardwareProfile()
        self.startObserving()
    }

    deinit {
        streamingTask?.cancel()
        filterTask?.cancel()
    }

    private func startObserving() {
        streamingTask?.cancel()
        streamingTask = Task { [weak self] in
            guard let scheduler = self?.scheduler else { return }
            let stream = await scheduler.metricsStream()
            for await snapshot in stream {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                self.handleNewMetrics(snapshot)
            }
        }
    }

    private func handleNewMetrics(_ snapshot: SystemMetrics) {
        self.metrics = snapshot

        // Append to 60-second fixed-capacity rolling buffers in O(1) time
        cpuHistory.append(snapshot.cpu.totalUsage)
        gpuHistory.append(snapshot.gpu.deviceUtilization)
        memoryHistory.append(snapshot.memory.usedPercentage)
        socTemperatureHistory.append(snapshot.thermal.socDieTemperature ?? 0.0)
        downloadSpeedHistory.append(snapshot.network.downloadBytesPerSecond)
        uploadSpeedHistory.append(snapshot.network.uploadBytesPerSecond)
        diskReadHistory.append(snapshot.disk.readBytesPerSecond)
        diskWriteHistory.append(snapshot.disk.writeBytesPerSecond)

        // Append to extended 15-minute rolling buffers (capacity 900)
        cpuHistory15m.append(snapshot.cpu.totalUsage)
        gpuHistory15m.append(snapshot.gpu.deviceUtilization)
        memoryHistory15m.append(snapshot.memory.usedPercentage)
        socTemperatureHistory15m.append(snapshot.thermal.socDieTemperature ?? 0.0)
        downloadSpeedHistory15m.append(snapshot.network.downloadBytesPerSecond)
        uploadSpeedHistory15m.append(snapshot.network.uploadBytesPerSecond)
        diskReadHistory15m.append(snapshot.disk.readBytesPerSecond)
        diskWriteHistory15m.append(snapshot.disk.writeBytesPerSecond)

        // Evaluate intelligent threshold alerts
        let alertConfig = AlertConfiguration(
            cpuThreshold: userSettings.cpuAlertThreshold,
            cpuAlertsEnabled: userSettings.cpuAlertEnabled,
            memoryUsageThreshold: 90.0,
            memoryPressureAlertsEnabled: userSettings.memoryPressureAlertEnabled,
            thermalThreshold: userSettings.thermalAlertThreshold,
            thermalAlertsEnabled: userSettings.thermalAlertEnabled,
            diskThreshold: 95.0,
            diskAlertsEnabled: true,
            cooldownInterval: 60.0
        )
        let (newAlerts, updatedFired) = AlertEvaluator.evaluate(
            metrics: snapshot,
            config: alertConfig,
            lastFired: alertLastFired
        )
        self.alertLastFired = updatedFired
        for alert in newAlerts {
            self.activeAlerts.insert(alert, at: 0)
            self.alertHistory.insert(alert, at: 0)
        }
        if alertHistory.count > 50 {
            alertHistory = Array(alertHistory.prefix(50))
        }

        scheduleProcessFilter()
    }

    public func historySlice(for buffer: RingBuffer<Double>, range: HistoryTimelineRange) -> [Double] {
        Array(buffer.suffix(range.sampleCount))
    }

    public func dismissAlert(id: UUID) {
        activeAlerts.removeAll { $0.id == id }
    }

    public func clearAllAlerts() {
        activeAlerts.removeAll()
    }

    public func refreshHardwareProfile() {
        self.hardwareProfile = DarwinMachBridge.fetchHardwareProfile()
    }

    public func inspect(process: ProcessItem) {
        self.inspectingProcess = process
    }

    @discardableResult
    public func pauseProcess(pid: pid_t, name: String? = nil) -> ProcessActionResult {
        let res = ProcessAction.pause(pid: pid, name: name)
        switch res {
        case .success:
            self.lastActionResultMessage = "Paused: \(name ?? "\(pid)") (\(pid))"
        case .failure(let reason):
            self.lastActionResultMessage = "Failed: \(reason)"
        }
        return res
    }

    @discardableResult
    public func resumeProcess(pid: pid_t, name: String? = nil) -> ProcessActionResult {
        let res = ProcessAction.resume(pid: pid, name: name)
        switch res {
        case .success:
            self.lastActionResultMessage = "Resumed: \(name ?? "\(pid)") (\(pid))"
        case .failure(let reason):
            self.lastActionResultMessage = "Failed: \(reason)"
        }
        return res
    }

    public var thermalMetrics: ThermalMetrics {
        metrics.thermal
    }

    // MARK: - Background Process Filtering & Sorting

    public func scheduleProcessFilter() {
        filterTask?.cancel()
        let rawProcesses = metrics.processes
        let query = searchText
        let category = selectedCategory
        let field = sortField
        let ascending = sortAscending

        filterTask = Task.detached(priority: .userInitiated) { [weak self] in
            let filtered = Self.filterAndSortProcesses(
                processes: rawProcesses,
                query: query,
                category: category,
                sortField: field,
                sortAscending: ascending
            )
            guard !Task.isCancelled else { return }
            await self?.updateFilteredProcesses(filtered)
        }
    }

    private func updateFilteredProcesses(_ processes: [ProcessItem]) {
        self.filteredProcesses = processes
    }

    public nonisolated static func filterAndSortProcesses(
        processes: [ProcessItem],
        query: String,
        category: ProcessCategory,
        sortField: ProcessSortField,
        sortAscending: Bool
    ) -> [ProcessItem] {
        // 1. Filter by category
        let categoryFiltered: [ProcessItem]
        switch category {
        case .all:
            categoryFiltered = processes
        case .highLoad:
            categoryFiltered = processes.compactMap { item in
                let matchesSelf = item.totalCPU > 5.0 || item.cpuPercentage > 5.0 || item.totalMemory > (500 * 1024 * 1024)
                let matchingChildren = item.children.filter { $0.totalCPU > 5.0 || $0.cpuPercentage > 5.0 || $0.totalMemory > (500 * 1024 * 1024) }
                if matchesSelf {
                    return item
                } else if !matchingChildren.isEmpty {
                    var copy = item
                    copy.children = matchingChildren
                    return copy
                }
                return nil
            }
        case .apps, .daemons, .system:
            categoryFiltered = processes.compactMap { item in
                let matchesSelf = item.category == category
                let matchingChildren = item.children.filter { $0.category == category }
                if matchesSelf {
                    return item
                } else if !matchingChildren.isEmpty {
                    var copy = item
                    copy.children = matchingChildren
                    return copy
                }
                return nil
            }
        }

        // 2. Filter by search query (checks parent and children)
        let filtered: [ProcessItem]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            filtered = categoryFiltered
        } else {
            filtered = categoryFiltered.compactMap { item in
                let matchesSelf = item.name.lowercased().contains(trimmed) ||
                                  "\(item.id)".contains(trimmed) ||
                                  item.ownerUser.lowercased().contains(trimmed) ||
                                  item.architecture.lowercased().contains(trimmed)
                let matchingChildren = item.children.filter {
                    $0.name.lowercased().contains(trimmed) ||
                    "\($0.id)".contains(trimmed) ||
                    $0.ownerUser.lowercased().contains(trimmed) ||
                    $0.architecture.lowercased().contains(trimmed)
                }

                if matchesSelf {
                    return item
                } else if !matchingChildren.isEmpty {
                    var copy = item
                    copy.children = matchingChildren
                    return copy
                } else {
                    return nil
                }
            }
        }

        // 3. Sort based on sortField and sortAscending
        return filtered.sorted { a, b in
            switch sortField {
            case .cpu:
                return sortAscending ? (a.totalCPU < b.totalCPU) : (a.totalCPU > b.totalCPU)
            case .memory:
                return sortAscending ? (a.totalMemory < b.totalMemory) : (a.totalMemory > b.totalMemory)
            case .name:
                let comp = a.name.localizedCaseInsensitiveCompare(b.name)
                return sortAscending ? (comp == .orderedAscending) : (comp == .orderedDescending)
            case .pid:
                return sortAscending ? (a.id < b.id) : (a.id > b.id)
            case .diskIO:
                return sortAscending ? (a.totalDiskBytesPerSecond < b.totalDiskBytesPerSecond) : (a.totalDiskBytesPerSecond > b.totalDiskBytesPerSecond)
            }
        }
    }

    // MARK: - Window Visibility & Occlusion

    public func setWindowVisible(_ isVisible: Bool) {
        self.isWindowVisible = isVisible
    }

    public func setWindowOccluded(_ isOccluded: Bool) {
        self.isWindowVisible = !isOccluded
    }

    private func updateSchedulerMode() {
        let isWindowActiveAndVisible = isDashboardWindowOpen && isWindowVisible
        let shouldRunFull = isPopoverOpen || isWindowActiveAndVisible
        Task { [weak self] in
            guard let scheduler = self?.scheduler else { return }
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
        guard let release = pendingUpdate,
              let url = SafeURLValidator.validate(urlString: release.htmlUrl) else {
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

    // MARK: - Two-Step Destructive Action Confirmation

    /// Requests confirmation for quitting or force-killing a process or group.
    public func requestProcessTermination(
        pid: pid_t,
        name: String,
        force: Bool = false,
        isGroup: Bool = false,
        childCount: Int = 0
    ) {
        self.pendingTermination = ProcessTerminationRequest(
            id: pid,
            name: name,
            isForce: force,
            isGroup: isGroup,
            childCount: childCount
        )
        self.showTerminationConfirmation = true
    }

    /// Confirms and executes the currently pending process termination request.
    @discardableResult
    public func confirmProcessTermination() -> ProcessActionResult? {
        guard let req = pendingTermination else { return nil }
        defer {
            self.pendingTermination = nil
            self.showTerminationConfirmation = false
        }
        let res: ProcessActionResult
        if req.isForce {
            res = ProcessAction.forceKill(pid: req.id, name: req.name)
        } else {
            res = ProcessAction.terminate(pid: req.id, name: req.name)
        }
        switch res {
        case .success:
            let verb = req.isForce ? "Force quit" : "Terminated"
            self.lastActionResultMessage = "\(verb): \(req.name) (\(req.id))"
        case .failure(let reason):
            self.lastActionResultMessage = "Failed: \(reason)"
        }
        return res
    }

    /// Cancels any pending process termination confirmation dialog.
    public func cancelProcessTermination() {
        self.pendingTermination = nil
        self.showTerminationConfirmation = false
    }

    /// Directly confirms and executes process termination with ProcessGuard checks.
    @discardableResult
    public func confirmProcessTermination(pid: pid_t, name: String, force: Bool = false) -> ProcessActionResult {
        let res = force ? ProcessAction.forceKill(pid: pid, name: name) : ProcessAction.terminate(pid: pid, name: name)
        switch res {
        case .success:
            let verb = force ? "Force quit" : "Terminated"
            self.lastActionResultMessage = "\(verb): \(name) (\(pid))"
        case .failure(let reason):
            self.lastActionResultMessage = "Failed: \(reason)"
        }
        return res
    }

    // MARK: - App Actions

    public func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

/// Represents an explicit pending request for destructive process termination.
public struct ProcessTerminationRequest: Identifiable, Equatable, Sendable {
    public let id: pid_t
    public let name: String
    public let isForce: Bool
    public let isGroup: Bool
    public let childCount: Int

    public init(
        id: pid_t,
        name: String,
        isForce: Bool = false,
        isGroup: Bool = false,
        childCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.isForce = isForce
        self.isGroup = isGroup
        self.childCount = childCount
    }
}
