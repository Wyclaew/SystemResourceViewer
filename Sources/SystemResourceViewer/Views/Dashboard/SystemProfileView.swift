import AppKit
import SwiftUI

/// Detailed Hardware and Operating System profile view.
public struct SystemProfileView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var copyFeedback: Bool = false

    public init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
    }

    private var profile: HardwareProfile {
        viewModel.hardwareProfile
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header with quick actions
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.marketingModelName)
                            .font(.system(size: 20, weight: .bold))
                        Text("Model: \(profile.modelIdentifier) • \(profile.cpuBrand)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        ExportManager.copyToClipboard(profile.generateReport())
                        copyFeedback = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            copyFeedback = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: copyFeedback ? "checkmark" : "doc.on.doc")
                            Text(copyFeedback ? "Copied!" : "Copy Profile")
                        }
                    }

                    Button {
                        let sysInfoURL = URL(fileURLWithPath: "/System/Applications/Utilities/System Information.app")
                        NSWorkspace.shared.open(sysInfoURL)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.right.square")
                            Text("System Info...")
                        }
                    }
                }
                .padding(.horizontal, 4)

                // 1. Hardware Overview Card
                profileCard(title: "Hardware Specifications", icon: "macbook.and.iphone") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        profileRow(label: "Mac Model", value: profile.marketingModelName)
                        profileRow(label: "Model Identifier", value: profile.modelIdentifier)
                        profileRow(label: "Processor / SoC", value: profile.cpuBrand)
                        profileRow(label: "Total Cores", value: "\(profile.totalCores) Cores")
                        profileRow(label: "Core Architecture", value: "\(profile.performanceCores) Performance + \(profile.efficiencyCores) Efficiency")
                        profileRow(label: "Unified Memory", value: Formatters.formatBytes(profile.totalMemoryBytes))
                    }
                }

                // 2. Operating System & Kernel Card
                profileCard(title: "Operating System & Darwin Kernel", icon: "gearshape.2") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        profileRow(label: "macOS Version", value: profile.osVersionString)
                        profileRow(label: "Build Number", value: profile.osBuildVersion)
                        profileRow(label: "Darwin Kernel", value: profile.kernelRelease)
                        profileRow(label: "Architecture", value: "arm64 / Apple Silicon")
                    }
                }

                // 3. System Boot & Uptime Card
                profileCard(title: "System Boot & Telemetry", icon: "clock.arrow.circlepath") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        profileRow(label: "Boot Timestamp", value: profile.bootTime.formatted(date: .abbreviated, time: .standard))
                        profileRow(label: "System Uptime", value: Formatters.formatUptime(DarwinMachBridge.fetchSystemUptime()))
                        profileRow(label: "Active Processes", value: "\(viewModel.metrics.processes.count) processes")
                        profileRow(label: "Primary Network Interface", value: viewModel.metrics.network.primaryInterfaceName)
                    }
                }
            }
            .padding(16)
        }
        .onAppear {
            viewModel.refreshHardwareProfile()
        }
    }

    private func profileCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                Spacer()
            }

            Divider()

            content()
        }
        .padding(14)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func profileRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }
}
