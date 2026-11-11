import SwiftUI

/// Detailed Network Telemetry card for the dashboard and popover.
public struct NetworkDashboardSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    private let isCompact: Bool

    public init(viewModel: DashboardViewModel, isCompact: Bool = false) {
        self.viewModel = viewModel
        self.isCompact = isCompact
    }

    private var network: NetworkMetrics {
        viewModel.metrics.network
    }

    public var body: some View {
        CardContainer {
            // Header
            SectionHeaderView(
                title: "Network Telemetry",
                symbol: network.interfaceType.systemSymbolName,
                symbolColor: AdaptiveColor.optimal
            ) {
                HStack(spacing: 6) {
                    // Interface Type Badge
                    HStack(spacing: 3) {
                        Image(systemName: network.interfaceType.systemSymbolName)
                            .font(.system(size: 10))
                        Text("\(network.interfaceType.rawValue) (\(network.primaryInterfaceName))")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())

                    // Latency Badge
                    HStack(spacing: 3) {
                        Circle()
                            .fill(network.latencyMilliseconds != nil ? AdaptiveColor.optimal : Color.gray)
                            .frame(width: 5, height: 5)
                        Text(Formatters.formatLatency(network.latencyMilliseconds))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(Capsule())
                }
            }

            // Speeds & IP
            HStack(spacing: 16) {
                // Download Speed Block
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AdaptiveColor.optimal)
                        Text("Download (Rx)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Text(Formatters.formatSpeed(network.downloadBytesPerSecond))
                        .font(.system(size: isCompact ? 16 : 18, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.primary)

                    MetricSparklineView(
                        values: viewModel.downloadSpeedHistory,
                        tintColor: AdaptiveColor.optimal,
                        fixedMax: nil,
                        height: 28
                    )
                }

                // Upload Speed Block
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.blue)
                        Text("Upload (Tx)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Text(Formatters.formatSpeed(network.uploadBytesPerSecond))
                        .font(.system(size: isCompact ? 16 : 18, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.primary)

                    MetricSparklineView(
                        values: viewModel.uploadSpeedHistory,
                        tintColor: Color.blue,
                        fixedMax: nil,
                        height: 28
                    )
                }
            }

            // Local IPv4 info footer
            Divider().opacity(0.5)

            HStack {
                Text("Local IPv4:")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(network.localIPv4)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                Spacer()

                Text("Auto-scaling bandwidth")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
