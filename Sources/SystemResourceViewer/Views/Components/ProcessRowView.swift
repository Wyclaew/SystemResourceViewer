import SwiftUI

/// Display mode for the process row metric badge.
public enum ProcessMetricMode {
    case cpu
    case memory
    case both
}

/// A hierarchical row presenting an active process with Task Manager-style stacking and disclosure arrow.
public struct ProcessRowView: View {
    private let process: ProcessItem
    private let mode: ProcessMetricMode
    private let isChild: Bool
    private let onAction: ((String) -> Void)?
    @Binding private var expandedPIDs: Set<pid_t>

    @State private var isHovered: Bool = false
    @State private var showingForceKillAlert: Bool = false
    @State private var showingGroupForceKillAlert: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showingErrorAlert: Bool = false

    private var isExpanded: Bool {
        expandedPIDs.contains(process.id)
    }

    public init(
        process: ProcessItem,
        mode: ProcessMetricMode = .both,
        isChild: Bool = false,
        expandedPIDs: Binding<Set<pid_t>> = .constant([]),
        onAction: ((String) -> Void)? = nil
    ) {
        self.process = process
        self.mode = mode
        self.isChild = isChild
        self._expandedPIDs = expandedPIDs
        self.onAction = onAction
    }

    /// Children that actually consume resources (filter out 0 CPU / 0 memory noise).
    private var activeChildren: [ProcessItem] {
        process.children.filter { $0.cpuPercentage > 0.01 || $0.memoryBytes > 0 }
    }

    private var hasActiveChildren: Bool {
        !activeChildren.isEmpty
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Main Process Row
            HStack(spacing: 6) {
                // Disclosure indicator
                if hasActiveChildren {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isHovered ? .primary : .secondary)
                        .frame(width: 22, height: 22)
                        .background(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else if isChild {
                    Text("└")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 22, height: 22)
                } else {
                    Spacer().frame(width: 22)
                }

                // App Icon
                Group {
                    if process.id < 0 {
                        Image(systemName: "apple.logo")
                            .resizable()
                            .scaledToFit()
                            .padding(2)
                            .foregroundStyle(.secondary)
                    } else if let icon = process.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                    } else {
                        Image(systemName: "app.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: isChild ? 16 : 20, height: isChild ? 16 : 20)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                // Name and Child Count Badge
                HStack(spacing: 4) {
                    Text(process.name)
                        .font(.system(size: isChild ? 11 : 12, weight: hasActiveChildren ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(isChild ? .secondary : .primary)

                    if hasActiveChildren {
                        Text("(\(activeChildren.count))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                }

                // PID Badge
                Text(process.id < 0 ? "System" : "\(process.id)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                // Metadata Badges (shown only for valid processes)
                if process.id > 0 {
                    // Architecture Badge
                    Text(process.isRosetta ? "Rosetta 2" : "Apple Silicon")
                        .font(.system(size: 8.5, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            process.isRosetta ?
                                Color.orange.opacity(0.15) :
                                AdaptiveColor.pCore.opacity(0.12)
                        )
                        .foregroundStyle(
                            process.isRosetta ?
                                Color.orange :
                                AdaptiveColor.pCore
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    // Owner Username
                    if !process.ownerUser.isEmpty {
                        Text(process.ownerUser)
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 2)
                    }

                    // Thread Count (in .both mode)
                    if mode == .both && process.threadCount > 0 {
                        Text("\(process.threadCount) th")
                            .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                // Metrics
                let cpuDisplay = hasActiveChildren ? process.formattedTotalCPU : process.formattedCPU
                let memDisplay = hasActiveChildren ? process.formattedTotalMemory : process.formattedMemory
                let cpuValue = hasActiveChildren ? process.totalCPU : process.cpuPercentage

                switch mode {
                case .cpu:
                    Text(cpuDisplay)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(cpuValue > 40.0 ? AdaptiveColor.critical : .secondary)

                case .memory:
                    Text(memDisplay)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                case .both:
                    HStack(spacing: 12) {
                        Text(cpuDisplay)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(cpuValue > 40.0 ? AdaptiveColor.critical : .secondary)
                            .frame(width: 58, alignment: .trailing)

                        Text(memDisplay)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .trailing)
                    }
                }

                // Hover terminate button (only for real, non-root/init processes)
                if isHovered && process.id > 1 {
                    Button {
                        terminateCurrentProcess(force: false)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Quit Process (SIGTERM)")
                    .transition(.opacity)
                }
            }
            .padding(.vertical, isChild ? 2 : 5)
            .padding(.horizontal, 6)
            .padding(.leading, isChild ? 20 : 0)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if hasActiveChildren {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if isExpanded {
                            expandedPIDs.remove(process.id)
                        } else {
                            expandedPIDs.insert(process.id)
                        }
                    }
                }
            }
            .onHover { isHovered = $0 }
            // Right-Click Context Menu
            .contextMenu {
                if process.id > 1 {
                    Button {
                        terminateCurrentProcess(force: false)
                    } label: {
                        Label("Quit (SIGTERM)", systemImage: "xmark.circle")
                    }

                    Button(role: .destructive) {
                        showingForceKillAlert = true
                    } label: {
                        Label("Force Quit...", systemImage: "xmark.octagon.fill")
                    }

                    if hasActiveChildren {
                        Divider()

                        Button(role: .destructive) {
                            terminateEntireGroup(force: false)
                        } label: {
                            Label("Quit Entire Group (\(activeChildren.count + 1) Processes)", systemImage: "square.stack.3d.down.right.fill")
                        }

                        Button(role: .destructive) {
                            showingGroupForceKillAlert = true
                        } label: {
                            Label("Force Quit Entire Group...", systemImage: "xmark.square.fill")
                        }
                    }

                    Divider()

                    Button {
                        ProcessAction.revealInFinder(pid: process.id)
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }

                    Button {
                        ProcessAction.copyPIDToClipboard(pid: process.id)
                        onAction?("Copied PID: \(process.id)")
                    } label: {
                        Label("Copy PID (\(process.id))", systemImage: "doc.on.doc")
                    }
                } else {
                    Label("macOS System Component", systemImage: "apple.logo")
                    Text("This process runs at the system/kernel level and cannot be terminated.")
                        .font(.caption)
                }
            }
            // Confirmation Alert Dialogs
            .confirmationDialog(
                "Force Quit \"\(process.name)\"?",
                isPresented: $showingForceKillAlert,
                titleVisibility: .visible
            ) {
                Button("Force Quit", role: .destructive) {
                    terminateCurrentProcess(force: true)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Do you want to force quit this process (PID \(process.id))? Any unsaved changes will be lost.")
            }
            .confirmationDialog(
                "Force Quit Group \"\(process.name)\"?",
                isPresented: $showingGroupForceKillAlert,
                titleVisibility: .visible
            ) {
                Button("Force Quit All (\(activeChildren.count + 1) Processes)", role: .destructive) {
                    terminateEntireGroup(force: true)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Do you want to forcefully terminate \(process.name) and its \(activeChildren.count) child processes? Any unsaved changes will be lost.")
            }
            // Error Alert Dialog
            .alert("Process Action Failed", isPresented: $showingErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred while communicating with the process.")
            }

            // Nested Sub-processes
            if isExpanded && hasActiveChildren {
                VStack(spacing: 1) {
                    ForEach(activeChildren) { child in
                        ProcessRowView(
                            process: child,
                            mode: mode,
                            isChild: true,
                            expandedPIDs: $expandedPIDs,
                            onAction: onAction
                        )
                        .id(child.id)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func terminateCurrentProcess(force: Bool) {
        guard process.id > 1 else {
            errorMessage = "Cannot terminate system initialization process (PID \(process.id))."
            showingErrorAlert = true
            return
        }
        let result: ProcessActionResult = force ? ProcessAction.forceKill(pid: process.id) : ProcessAction.terminate(pid: process.id)
        switch result {
        case .success:
            let verb = force ? "Force quit" : "Terminated"
            onAction?("\(verb): \(process.name) (\(process.id))")
        case .failure(let reason):
            errorMessage = reason
            showingErrorAlert = true
        }
    }

    private func terminateEntireGroup(force: Bool) {
        guard process.id > 1 else {
            errorMessage = "Cannot terminate system initialization process (PID \(process.id))."
            showingErrorAlert = true
            return
        }

        var failureReasons: [String] = []

        for child in process.children {
            guard child.id > 1 else { continue }
            let res: ProcessActionResult = force ? ProcessAction.forceKill(pid: child.id) : ProcessAction.terminate(pid: child.id)
            if case .failure(let msg) = res {
                failureReasons.append("\(child.name): \(msg)")
            }
        }

        let parentRes: ProcessActionResult = force ? ProcessAction.forceKill(pid: process.id) : ProcessAction.terminate(pid: process.id)
        if case .failure(let msg) = parentRes {
            failureReasons.append("\(process.name): \(msg)")
        }

        if failureReasons.isEmpty {
            let verb = force ? "Force quit" : "Terminated"
            onAction?("\(verb) group: \(process.name) (\(process.children.count + 1) processes)")
        } else {
            errorMessage = failureReasons.joined(separator: "\n")
            showingErrorAlert = true
        }
    }
}
