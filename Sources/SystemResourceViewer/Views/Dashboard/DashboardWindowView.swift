import AppKit
import SwiftUI

/// Sorting attributes for the hierarchical process monitor.
public enum ProcessSortField {
    case name
    case pid
    case cpu
    case memory
}

/// A clean, minimalist system monitor dashboard inspired by a modern Activity Monitor & Task Manager.
public struct DashboardWindowView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var searchText: String = ""
    @State private var selectedCategory: ProcessCategory = .all
    @State private var sortField: ProcessSortField = .cpu
    @State private var sortAscending: Bool = false
    @State private var statusFeedback: String?
    @State private var statusFeedbackTimer: Task<Void, Never>?
    @State private var stableProcessList: [ProcessItem] = []
    @State private var expandedPIDs: Set<pid_t> = []

    public init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
    }

    private func computeProcessList() -> [ProcessItem] {
        let list = viewModel.metrics.processes

        // 1. Filter by category
        let categoryFiltered: [ProcessItem]
        switch selectedCategory {
        case .all:
            categoryFiltered = list
        case .highLoad:
            categoryFiltered = list.compactMap { item in
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
            categoryFiltered = list.compactMap { item in
                let matchesSelf = item.category == selectedCategory
                let matchingChildren = item.children.filter { $0.category == selectedCategory }
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
        if searchText.isEmpty {
            filtered = categoryFiltered
        } else {
            let query = searchText.lowercased()
            filtered = categoryFiltered.compactMap { item in
                let matchesSelf = item.name.lowercased().contains(query) ||
                                  "\(item.id)".contains(query) ||
                                  item.ownerUser.lowercased().contains(query) ||
                                  item.architecture.lowercased().contains(query)
                let matchingChildren = item.children.filter {
                    $0.name.lowercased().contains(query) ||
                    "\($0.id)".contains(query) ||
                    $0.ownerUser.lowercased().contains(query) ||
                    $0.architecture.lowercased().contains(query)
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
            let result: Bool
            switch sortField {
            case .cpu:
                result = a.totalCPU > b.totalCPU
            case .memory:
                result = a.totalMemory > b.totalMemory
            case .name:
                result = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .pid:
                result = a.id < b.id
            }
            return sortAscending ? !result : result
        }
    }

    private func updateProcessList() {
        stableProcessList = computeProcessList()
    }

    private var totalChildProcessCount: Int {
        stableProcessList.reduce(0) { $0 + $1.children.count }
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

                    TextField("Search process, PID, user, arch...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
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
                            selectedCategory = category
                            updateProcessList()
                        } label: {
                            Text(category.rawValue)
                                .font(.system(size: 11, weight: selectedCategory == category ? .semibold : .regular))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    selectedCategory == category ?
                                        AdaptiveColor.pCore.opacity(0.18) :
                                        Color.primary.opacity(0.05)
                                )
                                .foregroundStyle(
                                    selectedCategory == category ?
                                        AdaptiveColor.pCore :
                                        .secondary
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
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
                columnHeaderButton(title: "CPU %", field: .cpu, width: 75, alignment: .trailing)

                // Memory column header
                columnHeaderButton(title: "Memory", field: .memory, width: 85, alignment: .trailing)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.03))

            Divider().opacity(0.5)

            // Hierarchical Process Tree with Right-Click Context Menu
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 1) {
                    ForEach(stableProcessList) { process in
                        ProcessRowView(
                            process: process,
                            mode: .both,
                            isChild: false,
                            expandedPIDs: $expandedPIDs,
                            onAction: { message in
                                showFeedback(message)
                            }
                        )
                        .id(process.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            Divider()

            // Bottom Status Bar
            HStack(spacing: 12) {
                Text("\(stableProcessList.count) root processes (\(totalChildProcessCount) child processes stacked)")
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
        .frame(minWidth: 780, minHeight: 540)
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
            updateProcessList()
        }
        .onDisappear {
            viewModel.isDashboardWindowOpen = false
        }
        .onChange(of: viewModel.metrics.processes) {
            updateProcessList()
        }
        .onChange(of: searchText) {
            updateProcessList()
        }
        .onChange(of: selectedCategory) {
            updateProcessList()
        }
        .onChange(of: sortField) {
            updateProcessList()
        }
        .onChange(of: sortAscending) {
            updateProcessList()
        }
    }

    private func columnHeaderButton(title: String, field: ProcessSortField, width: CGFloat?, alignment: Alignment) -> some View {
        Button {
            if sortField == field {
                sortAscending.toggle()
            } else {
                sortField = field
                sortAscending = (field == .name || field == .pid)
            }
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(sortField == field ? .primary : .secondary)

                if sortField == field {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: width, alignment: alignment)
        }
        .buttonStyle(.plain)
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
        .frame(maxWidth: .infinity)
    }
}
