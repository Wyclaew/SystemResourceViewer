import SwiftUI

/// Detailed Disk Storage and I/O throughput card for the dashboard and popover.
public struct DiskDashboardSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    private let isCompact: Bool

    public init(viewModel: DashboardViewModel, isCompact: Bool = false) {
        self.viewModel = viewModel
        self.isCompact = isCompact
    }

    private var disk: DiskMetrics {
        viewModel.metrics.disk
    }

    public var body: some View {
        CardContainer {
            // Header
            SectionHeaderView(
                title: "Storage & Disk I/O",
                symbol: "internaldrive",
                symbolColor: .cyan
            ) {
                Text(disk.volumeName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Top Row: Ring Gauge and Capacity Specs
            HStack(spacing: 14) {
                MetricRingGauge(
                    percentage: disk.usedPercentage,
                    title: "USED",
                    size: isCompact ? 56 : 64,
                    lineWidth: 6,
                    overrideColor: .cyan
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Used:")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(Formatters.formatBytes(disk.usedBytes))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                    }

                    HStack {
                        Text("Available:")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(Formatters.formatBytes(disk.freeBytes))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(AdaptiveColor.optimal)
                    }

                    HStack {
                        Text("Total:")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(Formatters.formatBytes(disk.totalBytes))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: 140)

                // Real-time Read / Write Speeds
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.cyan)
                        Text("Read:")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(Formatters.formatSpeed(disk.readBytesPerSecond))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.indigo)
                        Text("Write:")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(Formatters.formatSpeed(disk.writeBytesPerSecond))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            // Real-time Read/Write mini sparklines
            if !isCompact {
                Divider().opacity(0.5)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Read Throughput")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        MetricSparklineView(
                            values: viewModel.diskReadHistory,
                            tintColor: .cyan,
                            fixedMax: nil,
                            height: 32
                        )
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Write Throughput")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        MetricSparklineView(
                            values: viewModel.diskWriteHistory,
                            tintColor: .indigo,
                            fixedMax: nil,
                            height: 32
                        )
                    }
                }
            }
        }
    }
}
