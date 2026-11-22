import AppKit
import SwiftUI

/// Sorting attributes for the hierarchical process monitor.
public enum ProcessSortField: Sendable {
    case name
    case pid
    case cpu
    case memory
    case diskIO
}

/// A clean, minimalist system monitor dashboard inspired by a modern Activity Monitor & Task Manager.
public struct DashboardWindowView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var statusFeedback: String?
    @State private var statusFeedbackTimer: Task<Void, Never>?
    @State private var expandedPIDs: Set<pid_t> = []
    @FocusState private var isSearchFocused: Bool

    public init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
    }

    private var displayedProcessList: [ProcessItem] {
        if !viewModel.filteredProcesses.isEmpty {
            return viewModel.filteredProcesses
        } else if viewModel.searchText.isEmpty && viewModel.selectedCategory == .all {
            return viewModel.metrics.processes
        } else {
            return []
        }
    }

    private var totalChildProcessCount: Int {
        displayedProcessList.reduce(0) { $0 + $1.children.count }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Overview Metric Cards
            HStack(spacing: 12) {
                // CPU Summary Card
                miniSummaryCard(
                    title: "CPU",
                    symbol: "cpu",
                    symbolColor: AdaptiveColor.pCore,
                    percentage: viewModel.metrics.cpu.totalUsage,
                    mainValue: Formatters.formatPercentage(viewModel.metrics.cpu.totalUsage),
                    subValue: "\(viewModel.metrics.cpu.pCoreCount)P + \(viewModel.metrics.cpu.eCoreCount)E Cores"
                )

                // GPU Summary Card
                miniSummaryCard(
                    title: "GPU",
                    symbol: "display",
                    symbolColor: Color.purple,
                    percentage: viewModel.metrics.gpu.deviceUtilization,
                    mainValue: Formatters.formatPercentage(viewModel.metrics.gpu.deviceUtilization),
                    subValue: viewModel.metrics.gpu.coreCount > 0 ?
                        "\(viewModel.metrics.gpu.coreCount) Cores • \(Formatters.formatBytes(viewModel.metrics.gpu.inUseVRAMBytes))" :
                        Formatters.formatBytes(viewModel.metrics.gpu.inUseVRAMBytes)
                )

                // Memory (RAM) Summary Card
                miniSummaryCard(
                    title: "MEMORY",
                    symbol: "memorychip",
                    symbolColor: AdaptiveColor.forPressure(viewModel.metrics.memory.pressureLevel),
                    percentage: viewModel.metrics.memory.usedPercentage,
                    mainValue: "\(Formatters.formatBytes(viewModel.metrics.memory.usedBytes))",
                    subValue: "\(Formatters.formatBytes(viewModel.metrics.memory.totalBytes)) Total"
                )

                // Disk Storage Card
                miniSummaryCard(
                    title: "STORAGE",
                    symbol: "internaldrive",
                    symbolColor: .cyan,
                    percentage: viewModel.metrics.disk.usedPercentage,
                    mainValue: "\(Formatters.formatBytes(viewModel.metrics.disk.freeBytes)) Free",
                    subValue: "\(Formatters.formatBytes(viewModel.metrics.disk.totalBytes)) Total"
                )

                // Network & Power Card
                miniSummaryCard(
                    title: "NETWORK & POWER",
                    symbol: viewModel.metrics.network.interfaceType.systemSymbolName,
                    symbolColor: AdaptiveColor.optimal,
                    percentage: min(100.0, (viewModel.metrics.network.downloadBytesPerSecond / (10 * 1024 * 1024)) * 100.0),
                    mainValue: "↓ \(Formatters.formatSpeed(viewModel.metrics.network.downloadBytesPerSecond))",
                    subValue: viewModel.metrics.power.isBatteryInstalled ?
                        "Battery: \(viewModel.metrics.power.batteryPercentage)%" :
                        "AC Power (\(viewModel.metrics.power.thermalStateDescription))"
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.primary.opacity(0.02))

            Divider()

            // Resource Threshold Alert Banner (Milestone 3)
            if !viewModel.activeAlerts.isEmpty {
                ForEach(viewModel.activeAlerts.prefix(2)) { alert in
                    HStack(spacing: 8) {
                        Image(systemName: alert.severity.systemSymbolName)
                            .foregroundStyle(alert.severity == .critical ? Color.red : Color.orange)
                            .font(.system(size: 13, weight: .bold))

                        Text("\(alert.title): \(alert.message)")
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)

                        Spacer()

                        Button {
                            viewModel.dismissAlert(id: alert.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss \(alert.title) alert")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        alert.severity == .critical ?
                            Color.red.opacity(0.12) :
                            Color.orange.opacity(0.12)
                    )
                }
                Divider()
            }

            // Unified Multi-Tab Navigation Bar (Milestone 3)
            HStack {
                Picker("", selection: $viewModel.selectedTab) {
                    ForEach(DashboardTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.systemImage).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 440)

                Spacer()

                Button {
                    viewModel.isSettingsOpen = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11))
                        Text("Settings")
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: .command)
                .help("Settings & Preferences (⌘,)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.02))

            Divider()

            // Tab Content
            Group {
                switch viewModel.selectedTab {
                case .processes:
                    processesView
                case .diagnostics:
                    DiagnosticsView(viewModel: viewModel)
                case .history:
                    HistoryView(viewModel: viewModel)
                case .systemProfile:
                    SystemProfileView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Bottom Status Bar
            HStack(spacing: 12) {
                Text("\(displayedProcessList.count) root processes (\(totalChildProcessCount) child processes stacked)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text("•")
                    .foregroundStyle(.tertiary)

                Text("Apple Silicon • \(viewModel.metrics.cpu.pCoreCount)P + \(viewModel.metrics.cpu.eCoreCount)E Cores")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text("•")
                    .foregroundStyle(.tertiary)

                let tempStr = viewModel.metrics.thermal.socDieTemperature.map { String(format: "%.1f°C", $0) } ?? "Nominal"
                let coolingStr = viewModel.metrics.thermal.isFanless ? "Fanless (Passive)" : "\(viewModel.metrics.thermal.fanSpeeds.count) Fans"
                Text("Thermal: \(tempStr) (\(coolingStr))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Right-click a process row to quit or manage.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                Text("•")
                    .foregroundStyle(.tertiary)

                AuthorBadgeView(stateMachine: viewModel.easterEggStateMachine)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .sheet(item: $viewModel.inspectingProcess) { process in
            ProcessInspectorView(process: process, viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isSettingsOpen) {
            SettingsSheetView(viewModel: viewModel)
        }
        .preferredColorScheme(viewModel.userSettings.themeOverride.colorScheme)
        .frame(minWidth: 780, minHeight: 540)
        .background(
            WindowOcclusionObserver { isVisible in
                viewModel.setWindowVisible(isVisible)
            }
        )
        .background {
            // Standard macOS keyboard shortcuts: Cmd-1..4 for tabs, Cmd-F for process search
            Group {
                Button("") { viewModel.selectedTab = .processes }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { viewModel.selectedTab = .diagnostics }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { viewModel.selectedTab = .history }
                    .keyboardShortcut("3", modifiers: .command)
                Button("") { viewModel.selectedTab = .systemProfile }
                    .keyboardShortcut("4", modifiers: .command)
                Button("") {
                    if viewModel.selectedTab != .processes {
                        viewModel.selectedTab = .processes
                    }
                    isSearchFocused = true
                }
                .keyboardShortcut("f", modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { notification in
            if let window = notification.object as? NSWindow, window.isKeyWindow || window == NSApp.keyWindow {
                viewModel.setWindowVisible(window.occlusionState.contains(.visible))
            }
        }
        .alert(
            "New Version Available",
            isPresented: $viewModel.showUpdateConfirmation,
            presenting: viewModel.pendingUpdate
        ) { update in
            Button("Open Download Page") {
                viewModel.confirmUpdateAndOpenBrowser()
            }
            Button("Cancel", role: .cancel) {
                viewModel.showUpdateConfirmation = false
            }
        } message: { update in
            Text("Version \(update.tagName) is available on GitHub. Would you like to open the release page in your default browser to download it?")
        }
        .onAppear {
            viewModel.isDashboardWindowOpen = true
            viewModel.scheduleProcessFilter()
        }
        .onDisappear {
            viewModel.isDashboardWindowOpen = false
        }
    }

    private var processesView: some View {
        VStack(spacing: 0) {
            // Update Notification Banner (Milestone 2)
            if let update = viewModel.pendingUpdate {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("New Version Available:")
                                .font(.system(size: 12, weight: .bold))
                            Text(update.tagName)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.accentColor)
                        }

                        if !update.name.isEmpty && update.name != update.tagName {
                            Text(update.name)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Button {
                        viewModel.showUpdateConfirmation = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 11))
                            Text("Update...")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        viewModel.dismissUpdate()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss update notification")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.1))

                Divider()
            }

            // Toolbar: Search Bar, Category Filter Pills, Status Banner & Interval Control
            HStack(spacing: 12) {
                // Search Field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    TextField("Search process, PID, user, arch...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($isSearchFocused)
                        .accessibilityLabel("Process search field")

                    if !viewModel.searchText.isEmpty {
                        Button {
                            viewModel.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search text")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 240)

                // Category Filter Pills
                HStack(spacing: 5) {
                    ForEach(ProcessCategory.allCases) { category in
                        Button {
                            viewModel.selectedCategory = category
                        } label: {
                            Text(category.rawValue)
                                .font(.system(size: 11, weight: viewModel.selectedCategory == category ? .semibold : .regular))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    viewModel.selectedCategory == category ?
                                        AdaptiveColor.pCore.opacity(0.18) :
                                        Color.primary.opacity(0.05)
                                )
                                .foregroundStyle(
                                    viewModel.selectedCategory == category ?
                                        AdaptiveColor.pCore :
                                        .secondary
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(viewModel.selectedCategory == category ? [.isButton, .isSelected] : [.isButton])
                        .accessibilityLabel("\(category.rawValue) process category filter")
                    }
                }

                // Toast Feedback Badge
                if let feedback = statusFeedback {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(AdaptiveColor.optimal)
                        Text(feedback)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AdaptiveColor.optimal.opacity(0.12))
                    .clipShape(Capsule())
                    .transition(.opacity)
                }

                Spacer()

                // Check for Updates Button
                Button {
                    Task {
                        await viewModel.checkForUpdates()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if viewModel.isCheckingForUpdates {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(viewModel.isCheckingForUpdates ? "Checking..." : "Check for Updates")
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isCheckingForUpdates)
                .help("Check GitHub for application updates")

                // Refresh Interval Picker
                HStack(spacing: 4) {
                    Text("Refresh:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $viewModel.refreshInterval) {
                        Text("1 s").tag(1.0)
                        Text("2 s").tag(2.0)
                        Text("5 s").tag(5.0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 80)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Interactive Clickable Table Header for Sorting
            HStack(spacing: 8) {
                // Name column header
                columnHeaderButton(title: "Process Name", field: .name, width: nil, alignment: .leading)
                    .frame(minWidth: 200, alignment: .leading)

                // PID column header
                columnHeaderButton(title: "PID", field: .pid, width: 65, alignment: .leading)

                Spacer()

                // CPU column header
                columnHeaderButton(title: "CPU %", field: .cpu, width: 70, alignment: .trailing)

                // Memory column header
                columnHeaderButton(title: "Memory", field: .memory, width: 80, alignment: .trailing)

                // Disk I/O column header (Milestone 3)
                columnHeaderButton(title: "Disk I/O", field: .diskIO, width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.03))

            Divider().opacity(0.5)

            // Hierarchical Process Tree with Right-Click Context Menu or Empty State
            if displayedProcessList.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: viewModel.searchText.isEmpty ? "cpu" : "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text(viewModel.searchText.isEmpty ? "No Processes Available" : "No Matching Processes")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if !viewModel.searchText.isEmpty || viewModel.selectedCategory != .all {
                        Text("No process matched \"\(viewModel.searchText)\" in category \(viewModel.selectedCategory.rawValue).")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Button("Clear Filter & Search") {
                            viewModel.clearFilters()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 1) {
                        ForEach(displayedProcessList) { process in
                            ProcessRowView(
                                process: process,
                                mode: .both,
                                isChild: false,
                                expandedPIDs: $expandedPIDs,
                                onAction: { message in
                                    showFeedback(message)
                                },
                                onInspect: { item in
                                    viewModel.inspect(process: item)
                                }
                            )
                            .equatable()
                            .id(process.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func columnHeaderButton(title: String, field: ProcessSortField, width: CGFloat?, alignment: Alignment) -> some View {
        Button {
            if viewModel.sortField == field {
                viewModel.sortAscending.toggle()
            } else {
                viewModel.sortField = field
                viewModel.sortAscending = (field == .name || field == .pid)
            }
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(viewModel.sortField == field ? .primary : .secondary)

                if viewModel.sortField == field {
                    Image(systemName: viewModel.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: width, alignment: alignment)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(title)")
        .accessibilityValue(viewModel.sortField == field ? (viewModel.sortAscending ? "Sorted ascending" : "Sorted descending") : "Not sorted")
        .accessibilityHint("Click to sort table by \(title)")
    }

    private func showFeedback(_ message: String) {
        withAnimation {
            statusFeedback = message
        }
        statusFeedbackTimer?.cancel()
        statusFeedbackTimer = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation {
                statusFeedback = nil
            }
        }
    }

    private func miniSummaryCard(
        title: String,
        symbol: String,
        symbolColor: Color,
        percentage: Double,
        mainValue: String,
        subValue: String
    ) -> some View {
        HStack(spacing: 10) {
            MetricRingGauge(
                percentage: percentage,
                title: nil,
                size: 42,
                lineWidth: 4,
                overrideColor: symbolColor
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(symbolColor)
                    Text(title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                Text(mainValue)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                Text(subValue)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) Overview")
        .accessibilityValue("\(mainValue), \(subValue)")
        .accessibilityHint("System telemetry summary card")
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Window Occlusion Observer

struct WindowOcclusionObserver: NSViewRepresentable {
    let onOcclusionChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowObservingNSView()
        view.onOcclusionChange = onOcclusionChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    @MainActor
    final class WindowObservingNSView: NSView {
        var onOcclusionChange: (@MainActor (Bool) -> Void)?
        private var observerToken: (any NSObjectProtocol)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token = observerToken {
                NotificationCenter.default.removeObserver(token)
                observerToken = nil
            }
            guard let window = self.window else {
                onOcclusionChange?(false)
                return
            }
            onOcclusionChange?(window.occlusionState.contains(.visible))

            observerToken = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let window = window else { return }
                    let isVisible = window.occlusionState.contains(.visible)
                    self?.onOcclusionChange?(isVisible)
                }
            }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil, let token = observerToken {
                NotificationCenter.default.removeObserver(token)
                observerToken = nil
            }
        }
    }
}
