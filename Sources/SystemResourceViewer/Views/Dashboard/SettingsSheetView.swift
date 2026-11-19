import AppKit
import SwiftUI

/// User settings and preferences modal sheet with privacy, alert thresholds, and diagnostic exports.
public struct SettingsSheetView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var exportMessage: String?
    @State private var copyFeedback: Bool = false

    public init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings & Preferences")
                    .font(.system(size: 16, weight: .bold))

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    if let msg = exportMessage {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(msg)
                                .font(.system(size: 12))
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.green.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    // 1. General Preferences
                    settingsSection(title: "General", icon: "slider.horizontal.3") {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Telemetry Refresh Interval:")
                                    .font(.system(size: 12))
                                Spacer()
                                Picker("", selection: $viewModel.userSettings.refreshInterval) {
                                    Text("1.0 Second").tag(1.0)
                                    Text("2.0 Seconds (Default)").tag(2.0)
                                    Text("5.0 Seconds (Low Power)").tag(5.0)
                                }
                                .pickerStyle(.menu)
                                .frame(width: 180)
                            }

                            HStack {
                                Text("Default Startup Tab:")
                                    .font(.system(size: 12))
                                Spacer()
                                Picker("", selection: $viewModel.userSettings.startupTab) {
                                    ForEach(DashboardTab.allCases) { tab in
                                        Text(tab.rawValue).tag(tab.rawValue)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 180)
                            }

                            HStack {
                                Text("Theme Override:")
                                    .font(.system(size: 12))
                                Spacer()
                                Picker("", selection: $viewModel.userSettings.themeOverride) {
                                    ForEach(AppTheme.allCases) { theme in
                                        Text(theme.rawValue).tag(theme)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 200)
                            }
                        }
                    }

                    // 2. Resource Threshold Alerts
                    settingsSection(title: "Resource Threshold Alerts", icon: "exclamationmark.triangle") {
                        VStack(spacing: 14) {
                            Toggle("Enable High CPU Alerts", isOn: $viewModel.userSettings.cpuAlertEnabled)
                                .font(.system(size: 12))

                            if viewModel.userSettings.cpuAlertEnabled {
                                HStack {
                                    Text("CPU Threshold: \(Int(viewModel.userSettings.cpuAlertThreshold))%")
                                        .font(.system(size: 11, design: .monospaced))
                                        .frame(width: 140, alignment: .leading)
                                    Slider(value: $viewModel.userSettings.cpuAlertThreshold, in: 50...99, step: 1)
                                }
                            }

                            Divider()

                            Toggle("Enable Memory Pressure Alerts", isOn: $viewModel.userSettings.memoryPressureAlertEnabled)
                                .font(.system(size: 12))

                            Divider()

                            Toggle("Enable Thermal Throttling Alerts", isOn: $viewModel.userSettings.thermalAlertEnabled)
                                .font(.system(size: 12))

                            if viewModel.userSettings.thermalAlertEnabled {
                                HStack {
                                    Text("SoC Temp Threshold: \(Int(viewModel.userSettings.thermalAlertThreshold))°C")
                                        .font(.system(size: 11, design: .monospaced))
                                        .frame(width: 160, alignment: .leading)
                                    Slider(value: $viewModel.userSettings.thermalAlertThreshold, in: 60...105, step: 1)
                                }
                            }
                        }
                    }

                    // 3. Privacy & Security Protections
                    settingsSection(title: "Privacy & Sensitive Data", icon: "lock.shield") {
                        VStack(spacing: 12) {
                            Toggle("Mask API Tokens, Passwords & Sensitive CLI Arguments", isOn: $viewModel.userSettings.privacySettings.maskSensitiveArguments)
                                .font(.system(size: 12))

                            Toggle("Mask Local IPv4 Network Address", isOn: $viewModel.userSettings.privacySettings.maskLocalIPAddress)
                                .font(.system(size: 12))

                            Toggle("Hide macOS System Daemons & Root Processes", isOn: $viewModel.userSettings.privacySettings.hideSystemProcessesByDefault)
                                .font(.system(size: 12))

                            Toggle("Allow Lightweight Network Latency Probes (1.1.1.1:53)", isOn: $viewModel.userSettings.privacySettings.allowExternalSocketProbe)
                                .font(.system(size: 12))
                        }
                    }

                    // 4. Diagnostics & Reporting Export
                    settingsSection(title: "Diagnostics & Reporting", icon: "square.and.arrow.up") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Export telemetry snapshots or process listings with privacy masking applied.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                Button {
                                    saveCSVFile()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "tablecells")
                                        Text("Export CSV...")
                                    }
                                }

                                Button {
                                    saveJSONFile()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "curlybraces")
                                        Text("Export JSON...")
                                    }
                                }

                                Button {
                                    let md = ExportManager.exportMarkdownSummary(
                                        metrics: viewModel.metrics,
                                        hardwareProfile: viewModel.hardwareProfile,
                                        activeAlerts: viewModel.activeAlerts,
                                        privacySettings: viewModel.userSettings.privacySettings
                                    )
                                    ExportManager.copyToClipboard(md)
                                    copyFeedback = true
                                    exportMessage = "Markdown report copied to clipboard."
                                    Task {
                                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                                        copyFeedback = false
                                        exportMessage = nil
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: copyFeedback ? "checkmark" : "doc.on.doc")
                                        Text(copyFeedback ? "Copied!" : "Copy Markdown")
                                    }
                                }
                            }
                        }
                    }

                    // 5. Reset Defaults
                    HStack {
                        Spacer()
                        Button("Reset to Defaults") {
                            viewModel.userSettings = .defaultSettings
                            UserSettings.reset()
                            exportMessage = "Settings restored to defaults."
                            Task {
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                exportMessage = nil
                            }
                        }
                        .foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 540, minHeight: 520)
    }

    private func saveCSVFile() {
        let csvContent = ExportManager.exportProcessCSV(
            processes: viewModel.metrics.processes,
            privacySettings: viewModel.userSettings.privacySettings
        )
        let savePanel = NSSavePanel()
        savePanel.title = "Export Process List (CSV)"
        savePanel.nameFieldStringValue = "ProcessList-\(Int(Date().timeIntervalSince1970)).csv"
        savePanel.canCreateDirectories = true
        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? csvContent.write(to: url, atomically: true, encoding: .utf8)
            exportMessage = "Process table saved to \(url.lastPathComponent)."
        }
    }

    private func saveJSONFile() {
        let jsonContent = ExportManager.exportTelemetryJSON(
            metrics: viewModel.metrics,
            hardwareProfile: viewModel.hardwareProfile,
            privacySettings: viewModel.userSettings.privacySettings
        )
        let savePanel = NSSavePanel()
        savePanel.title = "Export System Telemetry Snapshot (JSON)"
        savePanel.nameFieldStringValue = "TelemetrySnapshot-\(Int(Date().timeIntervalSince1970)).json"
        savePanel.canCreateDirectories = true
        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? jsonContent.write(to: url, atomically: true, encoding: .utf8)
            exportMessage = "Telemetry JSON saved to \(url.lastPathComponent)."
        }
    }

    private func settingsSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
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
}
