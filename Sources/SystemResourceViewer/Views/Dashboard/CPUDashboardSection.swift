import SwiftUI

/// Detailed CPU telemetry card for the dashboard and popover.
public struct CPUDashboardSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    private let isCompact: Bool

    public init(viewModel: DashboardViewModel, isCompact: Bool = false) {
        self.viewModel = viewModel
        self.isCompact = isCompact
    }

    private var cpu: CPUMetrics {
        viewModel.metrics.cpu
    }

    public var body: some View {
        CardContainer {
            // Header
            SectionHeaderView(
                title: "Processor (CPU)",
                symbol: "cpu",
                symbolColor: AdaptiveColor.pCore
            ) {
                HStack(spacing: 6) {
                    if cpu.pCoreCount > 0 || cpu.eCoreCount > 0 {
                        Text("\(cpu.pCoreCount)P + \(cpu.eCoreCount)E")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                    }

                    Text(Formatters.formatPercentage(cpu.totalUsage))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(AdaptiveColor.forPercentage(cpu.totalUsage))
                }
            }

            // Top Row: Ring Gauge, Breakdown, and 60s Sparkline
            HStack(spacing: 14) {
                MetricRingGauge(
                    percentage: cpu.totalUsage,
                    title: "LOAD",
                    size: isCompact ? 56 : 64,
                    lineWidth: 6
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Circle().fill(Color.blue).frame(width: 6, height: 6)
                        Text("User:").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Text(Formatters.formatPercentage(cpu.userPercentage))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                    }

                    HStack {
                        Circle().fill(Color.purple).frame(width: 6, height: 6)
                        Text("System:").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Text(Formatters.formatPercentage(cpu.systemPercentage))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                    }

                    HStack {
                        Circle().fill(Color.gray.opacity(0.4)).frame(width: 6, height: 6)
                        Text("Idle:").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Text(Formatters.formatPercentage(cpu.idlePercentage))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: 120)

                // 60-second Sparkline
                VStack(alignment: .trailing, spacing: 2) {
                    MetricSparklineView(
                        values: viewModel.cpuHistory,
                        tintColor: AdaptiveColor.forPercentage(cpu.totalUsage),
                        fixedMax: 100.0,
                        height: isCompact ? 38 : 46
                    )
                    Text("Last 60 seconds")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            // Per-Core Bars (P-cores & E-cores)
            if !cpu.coreUsages.isEmpty {
                Divider().opacity(0.5)

                VStack(spacing: 6) {
                    // Split cores into rows of 2 for clean readability in full dashboard, or single column in compact
                    let visibleCores = isCompact ? Array(cpu.coreUsages.prefix(8)) : cpu.coreUsages
                    let columns = [GridItem(.flexible(), spacing: 10)]

                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(visibleCores) { core in
                            let displayNumber = core.type == .efficiency ?
                                core.coreIndex + 1 :
                                (core.coreIndex - cpu.eCoreCount + 1)
                            CoreUsageBarView(core: core, displayNumber: max(1, displayNumber))
                        }
                    }

                    if isCompact && cpu.coreUsages.count > 8 {
                        Text("+ \(cpu.coreUsages.count - 8) more cores in Dashboard")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }

            // Top CPU Processes
            if !cpu.topProcesses.isEmpty {
                Divider().opacity(0.5)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Top CPU Processes")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    let displayProcesses = isCompact ? Array(cpu.topProcesses.prefix(3)) : cpu.topProcesses
                    ForEach(displayProcesses) { process in
                        ProcessRowView(process: process, mode: .cpu)
                    }
                }
            }
        }
    }
}
