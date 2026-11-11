import SwiftUI

/// Detailed GPU telemetry card for the dashboard window and menu bar popover.
public struct GPUDashboardSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    private let isCompact: Bool

    public init(viewModel: DashboardViewModel, isCompact: Bool = false) {
        self.viewModel = viewModel
        self.isCompact = isCompact
    }

    private var gpu: GPUMetrics {
        viewModel.metrics.gpu
    }

    public var body: some View {
        CardContainer {
            // Header
            SectionHeaderView(
                title: "Graphics (GPU)",
                symbol: "display",
                symbolColor: Color.purple
            ) {
                HStack(spacing: 6) {
                    if gpu.coreCount > 0 {
                        Text("\(gpu.coreCount)-Core")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                    }

                    Text(Formatters.formatPercentage(gpu.deviceUtilization))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(AdaptiveColor.forPercentage(gpu.deviceUtilization))
                }
            }

            // Top Row: Ring Gauge, Engine Breakdown, and 60s Sparkline
            HStack(spacing: 14) {
                MetricRingGauge(
                    percentage: gpu.deviceUtilization,
                    title: "LOAD",
                    size: isCompact ? 56 : 64,
                    lineWidth: 6,
                    overrideColor: AdaptiveColor.forPercentage(gpu.deviceUtilization)
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Circle().fill(Color.purple).frame(width: 6, height: 6)
                        Text("Device:").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Text(Formatters.formatPercentage(gpu.deviceUtilization))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                    }

                    HStack {
                        Circle().fill(Color.teal).frame(width: 6, height: 6)
                        Text("Renderer:").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Text(Formatters.formatPercentage(gpu.rendererUtilization))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                    }

                    HStack {
                        Circle().fill(Color.orange).frame(width: 6, height: 6)
                        Text("Tiler:").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Text(Formatters.formatPercentage(gpu.tilerUtilization))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: 125)

                // 60-second Sparkline
                VStack(alignment: .trailing, spacing: 2) {
                    MetricSparklineView(
                        values: viewModel.gpuHistory,
                        tintColor: AdaptiveColor.forPercentage(gpu.deviceUtilization),
                        fixedMax: 100.0,
                        height: isCompact ? 38 : 46
                    )
                    Text("Last 60 seconds")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            // VRAM Utilization Bar
            if gpu.allocatedVRAMBytes > 0 {
                Divider().opacity(0.5)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 4) {
                            Text("VRAM")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)

                            if gpu.hasUnifiedMemory {
                                Text("Unified")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.primary.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }

                        Spacer()

                        Text("\(Formatters.formatBytes(gpu.inUseVRAMBytes)) / \(Formatters.formatBytes(gpu.allocatedVRAMBytes))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    // Custom progress track
                    GeometryReader { proxy in
                        let totalWidth = proxy.size.width
                        let usageRatio = min(1.0, max(0.0, Double(gpu.inUseVRAMBytes) / Double(max(1, gpu.allocatedVRAMBytes))))
                        let barWidth = totalWidth * CGFloat(usageRatio)

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.purple.opacity(0.85), Color.purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(2, barWidth), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
    }
}
