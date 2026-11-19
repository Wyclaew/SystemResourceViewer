import SwiftUI

/// Rich hardware diagnostics and telemetry dashboard view.
public struct DiagnosticsView: View {
    @ObservedObject var viewModel: DashboardViewModel

    public init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                CPUDashboardSection(viewModel: viewModel, isCompact: false)
                GPUDashboardSection(viewModel: viewModel, isCompact: false)
                MemoryDashboardSection(viewModel: viewModel, isCompact: false)
                ThermalDashboardSection(viewModel: viewModel, isCompact: false)
                DiskDashboardSection(viewModel: viewModel, isCompact: false)
                NetworkDashboardSection(viewModel: viewModel, isCompact: false)
                PowerDashboardSection(viewModel: viewModel, isCompact: false)
            }
            .padding(16)
        }
    }
}
