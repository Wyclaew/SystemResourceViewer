import AppKit
import SwiftUI

/// Compact MenuBar popover view inspired by iStat Menus and CleanMyMac.
public struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onOpenDashboard: () -> Void

    public init(viewModel: DashboardViewModel, onOpenDashboard: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onOpenDashboard = onOpenDashboard
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar Header
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AdaptiveColor.pCore)

                    Text("System Resources")
                        .font(.system(size: 13, weight: .bold))
                }

                Spacer()

                // Interval Picker Pill
                Picker("Interval", selection: $viewModel.refreshInterval) {
                    Text("1s").tag(1.0)
                    Text("2s").tag(2.0)
                    Text("5s").tag(5.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 110)

                // Expand to Full Window Button
                Button {
                    onOpenDashboard()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .padding(5)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .help("Open Full Diagnostics Dashboard")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // Update Notification Banner (Milestone 2)
            if let update = viewModel.pendingUpdate {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Update: \(update.tagName)")
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                    }

                    Spacer()

                    Button("Update...") {
                        viewModel.showUpdateConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)

                    Button {
                        viewModel.dismissUpdate()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12))

                Divider()
            }

            // Scrollable Sections
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    CPUDashboardSection(viewModel: viewModel, isCompact: true)
                    GPUDashboardSection(viewModel: viewModel, isCompact: true)
                    MemoryDashboardSection(viewModel: viewModel, isCompact: true)
                    ThermalDashboardSection(viewModel: viewModel, isCompact: true)
                    DiskDashboardSection(viewModel: viewModel, isCompact: true)
                    NetworkDashboardSection(viewModel: viewModel, isCompact: true)
                    PowerDashboardSection(viewModel: viewModel, isCompact: true)
                }
                .padding(12)
            }
            .frame(maxHeight: 520)

            Divider()

            // Bottom Footer
            HStack {
                Button {
                    let activityMonitorURL = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
                    NSWorkspace.shared.open(activityMonitorURL)
                } label: {
                    Label("Activity Monitor", systemImage: "chart.bar.xaxis")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Task {
                        await viewModel.checkForUpdates()
                    }
                } label: {
                    if viewModel.isCheckingForUpdates {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(viewModel.isCheckingForUpdates)
                .help("Check for Updates")

                Spacer()

                AuthorBadgeView(stateMachine: viewModel.easterEggStateMachine)

                Spacer()

                Button("Quit") {
                    viewModel.quitApp()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .frame(width: 360)
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
            Text("Version \(update.tagName) is available on GitHub. Would you like to view the release in your browser?")
        }
        .onAppear {
            viewModel.isPopoverOpen = true
        }
        .onDisappear {
            viewModel.isPopoverOpen = false
        }
        .preferredColorScheme(viewModel.userSettings.themeOverride.colorScheme)
    }
}
