import AppKit
import SwiftUI

/// Comprehensive modal inspection sheet presenting deep Darwin and Mach diagnostics for a process.
public struct ProcessInspectorView: View {
    @ObservedObject var viewModel: DashboardViewModel
    let initialProcess: ProcessItem

    @State private var detail: ProcessDetailItem
    @State private var refreshTimer: Task<Void, Never>?
    @State private var copyFeedback: Bool = false
    @State private var actionMessage: String?
    @State private var showingTerminateConfirm: Bool = false
    @State private var showingForceKillConfirm: Bool = false
    @Environment(\.dismiss) private var dismiss

    public init(process: ProcessItem, viewModel: DashboardViewModel) {
        self.initialProcess = process
        self.viewModel = viewModel
        self._detail = State(initialValue: DarwinMachBridge.fetchProcessDetail(for: process))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 12) {
                if let icon = initialProcess.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(detail.name)
                            .font(.system(size: 16, weight: .bold))
                            .lineLimit(1)

                        Text("PID: \(detail.id)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        if detail.isSuspended {
                            HStack(spacing: 3) {
                                Image(systemName: "pause.fill").font(.system(size: 8))
                                Text("Paused").font(.system(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.yellow.opacity(0.2))
                            .foregroundStyle(Color.yellow)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        } else {
                            Text("Running")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .foregroundStyle(Color.green)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        if detail.isProtected {
                            HStack(spacing: 3) {
                                Image(systemName: "lock.shield.fill").font(.system(size: 8))
                                Text("Protected").font(.system(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }

                    HStack(spacing: 8) {
                        Text("User: \(detail.ownerUser)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Text("•")
                            .foregroundStyle(.tertiary)

                        Text("Architecture: \(detail.architecture)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        if let bundleId = detail.bundleIdentifier {
                            Text("•")
                                .foregroundStyle(.tertiary)
                            Text(bundleId)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)

                Button("Dismiss", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .hidden()
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Diagnostics Content
            ScrollView {
                VStack(spacing: 16) {
                    // Action Feedback Banner
                    if let msg = actionMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                            Text(msg)
                                .font(.system(size: 12))
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    // 1. Compute & Threads Card
                    card(title: "CPU & Threads", icon: "cpu") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            statItem(label: "CPU Usage", value: String(format: "%.1f%%", detail.cpuPercentage), highlight: detail.cpuPercentage > 40.0)
                            statItem(label: "Active Threads", value: "\(detail.threadCount)")
                            statItem(label: "User Time", value: Formatters.formatNanoseconds(detail.userTimeNs))
                            statItem(label: "System Time", value: Formatters.formatNanoseconds(detail.systemTimeNs))
                            statItem(label: "Context Switches", value: "\(detail.contextSwitches)")
                            statItem(label: "Open Descriptors", value: detail.openFileDescriptorsCount.map { "\($0)" } ?? "N/A (Restricted)")
                        }
                    }

                    // 2. Memory Diagnostics Card
                    card(title: "Memory Footprint", icon: "memorychip") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            statItem(label: "Resident Memory (RSS)", value: detail.formattedResidentMemory)
                            statItem(label: "Virtual Memory (VSize)", value: detail.formattedVirtualMemory)
                            statItem(label: "Page Faults", value: "\(detail.faults)")
                            statItem(label: "Page-ins (Disk)", value: "\(detail.pageins)")
                            statItem(label: "Copy-On-Write Faults", value: "\(detail.cowFaults)")
                            statItem(label: "Mach Syscalls", value: "\(detail.machSyscalls)")
                        }
                    }

                    // 3. Disk Storage I/O Card
                    card(title: "Disk Storage I/O", icon: "internaldrive") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            statItem(label: "Read Throughput", value: detail.formattedDiskReadSpeed)
                            statItem(label: "Write Throughput", value: detail.formattedDiskWriteSpeed)
                            statItem(label: "Lifetime Disk Read", value: detail.formattedTotalDiskRead)
                            statItem(label: "Lifetime Disk Written", value: detail.formattedTotalDiskWrite)
                        }
                    }

                    // 4. Runtime & Process Environment Card
                    card(title: "Runtime & Kernel", icon: "terminal") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Parent PID (PPID):")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text("\(detail.ppid)")
                                    .font(.system(size: 11, design: .monospaced))
                                Spacer()
                                Text("Launch Time:")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text(detail.formattedStartTime)
                                    .font(.system(size: 11))
                            }

                            HStack {
                                Text("Uptime:")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text(detail.formattedUptime)
                                    .font(.system(size: 11))
                                Spacer()
                            }

                            if let path = detail.executablePath {
                                Divider().padding(.vertical, 2)
                                Text("Executable Binary Path:")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text(path)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            // Footer Execution Controls
            HStack(spacing: 10) {
                // Copy Diagnostics Button
                Button {
                    ExportManager.copyToClipboard(detail.formattedDiagnosticsSummary)
                    copyFeedback = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        copyFeedback = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copyFeedback ? "checkmark" : "doc.on.doc")
                        Text(copyFeedback ? "Copied!" : "Copy Diagnostics")
                    }
                }
                .keyboardShortcut("c", modifiers: .command)

                if detail.executablePath != nil {
                    Button {
                        ProcessAction.revealInFinder(pid: detail.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text("Reveal in Finder")
                        }
                    }
                }

                Spacer()

                // Process Control Buttons
                if detail.isProtected {
                    Text("Process is protected by system security policy.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                } else if detail.id > 1 {
                    // Pause / Resume Toggle
                    if detail.isSuspended {
                        Button {
                            resumeProcess()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                Text("Resume Process")
                            }
                        }
                    } else {
                        Button {
                            pauseProcess()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "pause.fill")
                                Text("Pause Process")
                            }
                        }
                    }

                    // Quit Button
                    Button("Quit...") {
                        showingTerminateConfirm = true
                    }

                    // Force Quit Button
                    Button("Force Quit...", role: .destructive) {
                        showingForceKillConfirm = true
                    }
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 580, minHeight: 520)
        .onAppear {
            startPolling()
        }
        .onDisappear {
            refreshTimer?.cancel()
        }
        .confirmationDialog(
            "Quit \"\(detail.name)\"?",
            isPresented: $showingTerminateConfirm,
            titleVisibility: .visible
        ) {
            Button("Quit", role: .destructive) {
                let res = ProcessAction.terminate(pid: detail.id, name: detail.name)
                handleActionResult(res, action: "Terminated")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to quit \(detail.name) (PID: \(detail.id))?")
        }
        .confirmationDialog(
            "Force Quit \"\(detail.name)\"?",
            isPresented: $showingForceKillConfirm,
            titleVisibility: .visible
        ) {
            Button("Force Quit", role: .destructive) {
                let res = ProcessAction.forceKill(pid: detail.id, name: detail.name)
                handleActionResult(res, action: "Force quit")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to force quit \(detail.name)? Unsaved data will be lost.")
        }
    }

    private func currentProcessItem() -> ProcessItem {
        for root in viewModel.metrics.processes {
            if root.id == initialProcess.id { return root }
            for child in root.children where child.id == initialProcess.id {
                return child
            }
        }
        return initialProcess
    }

    private func startPolling() {
        refreshTimer?.cancel()
        refreshTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { break }
                let current = await MainActor.run { currentProcessItem() }
                let updated = DarwinMachBridge.fetchProcessDetail(for: current)
                await MainActor.run {
                    self.detail = updated
                }
            }
        }
    }

    private func pauseProcess() {
        let res = ProcessAction.pause(pid: detail.id, name: detail.name)
        handleActionResult(res, action: "Paused")
        // Refresh immediately
        self.detail = DarwinMachBridge.fetchProcessDetail(for: currentProcessItem())
    }

    private func resumeProcess() {
        let res = ProcessAction.resume(pid: detail.id, name: detail.name)
        handleActionResult(res, action: "Resumed")
        self.detail = DarwinMachBridge.fetchProcessDetail(for: currentProcessItem())
    }

    private func handleActionResult(_ res: ProcessActionResult, action: String) {
        switch res {
        case .success:
            actionMessage = "\(action) successfully."
        case .failure(let reason):
            actionMessage = "Failed: \(reason)"
        }
    }

    private func card<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                Spacer()
            }

            content()
        }
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func statItem(label: String, value: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(highlight ? AdaptiveColor.critical : .primary)
        }
    }
}
