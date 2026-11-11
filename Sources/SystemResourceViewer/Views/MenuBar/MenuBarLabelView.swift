import SwiftUI

/// Compact menu bar label showing live mini-metrics directly in the macOS status bar.
public struct MenuBarLabelView: View {
    @ObservedObject var viewModel: DashboardViewModel

    public init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 8) {
            // CPU mini readout
            HStack(spacing: 3) {
                Image(systemName: "cpu")
                    .font(.system(size: 10, weight: .semibold))
                Text("\(Int(round(viewModel.metrics.cpu.totalUsage)))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
            }

            // RAM mini readout
            HStack(spacing: 3) {
                Image(systemName: "memorychip")
                    .font(.system(size: 10, weight: .semibold))
                Text("\(Int(round(viewModel.metrics.memory.usedPercentage)))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
            }

            // Network mini download speed
            HStack(spacing: 2) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .semibold))
                Text(Formatters.formatSpeed(viewModel.metrics.network.downloadBytesPerSecond))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
            }
        }
    }
}
