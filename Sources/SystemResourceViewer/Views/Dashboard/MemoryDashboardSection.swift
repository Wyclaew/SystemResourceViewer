import SwiftUI

/// Detailed Memory (RAM) telemetry card for the dashboard and popover.
public struct MemoryDashboardSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    private let isCompact: Bool

    public init(viewModel: DashboardViewModel, isCompact: Bool = false) {
        self.viewModel = viewModel
        self.isCompact = isCompact
    }

    private var memory: MemoryMetrics {
        viewModel.metrics.memory
    }

    public var body: some View {
        CardContainer {
            // Header
            SectionHeaderView(
                title: "Memory (RAM)",
                symbol: "memorychip",
                symbolColor: AdaptiveColor.forPressure(memory.pressureLevel)
            ) {
                HStack(spacing: 6) {
                    // Memory Pressure Indicator
                    HStack(spacing: 4) {
                        Image(systemName: memory.pressureLevel.systemSymbolName)
                            .font(.system(size: 11))
                        Text(memory.pressureLevel.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(AdaptiveColor.forPressure(memory.pressureLevel))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AdaptiveColor.forPressure(memory.pressureLevel).opacity(0.12))
                    .clipShape(Capsule())

                    Text("\(Formatters.formatBytes(memory.usedBytes)) / \(Formatters.formatBytes(memory.totalBytes))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            // Top Row: Ring Gauge, Breakdown, and 60s Sparkline
            HStack(spacing: 14) {
                MetricRingGauge(
                    percentage: memory.usedPercentage,
                    title: "USED",
                    size: isCompact ? 56 : 64,
                    lineWidth: 6,
                    overrideColor: AdaptiveColor.forPressure(memory.pressureLevel)
                )

                VStack(alignment: .leading, spacing: 3) {
                    metricLine(label: "App:", bytes: memory.appMemoryBytes, dotColor: .blue)
                    metricLine(label: "Wired:", bytes: memory.wiredBytes, dotColor: .red)
                    metricLine(label: "Compressed:", bytes: memory.compressedBytes, dotColor: .orange)
                    metricLine(label: "Cached:", bytes: memory.cachedBytes, dotColor: .green)
                    metricLine(label: "Swap Used:", bytes: memory.swapUsedBytes, dotColor: .purple)
                }
                .frame(maxWidth: 130)

                // 60-second Sparkline
                VStack(alignment: .trailing, spacing: 2) {
                    MetricSparklineView(
                        values: viewModel.memoryHistory,
                        tintColor: AdaptiveColor.forPressure(memory.pressureLevel),
                        fixedMax: 100.0,
                        height: isCompact ? 38 : 46
                    )
                    Text("Last 60 seconds")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            // Top Memory Processes
            if !memory.topProcesses.isEmpty {
                Divider().opacity(0.5)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Top Memory Applications")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    let displayProcesses = isCompact ? Array(memory.topProcesses.prefix(3)) : memory.topProcesses
                    ForEach(displayProcesses) { process in
                        ProcessRowView(process: process, mode: .memory)
                    }
                }
            }
        }
    }

    private func metricLine(label: String, bytes: UInt64, dotColor: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(dotColor).frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Text(Formatters.formatBytes(bytes))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }
}
