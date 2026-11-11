import Foundation
@testable import SystemResourceViewer

/// Process Category Filter enum matching PROJECT.md § Interface Contracts
public typealias ProcessCategory = SystemResourceViewer.ProcessCategory

public enum ProcessActionResultContract: Sendable, Equatable {
    case success
    case failure(String)
}

public struct ProcessFilterHelper {
    public static func filter(
        processes: [ProcessItem],
        category: ProcessCategory,
        searchQuery: String = ""
    ) -> [ProcessItem] {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return processes.filter { process in
            // 1. Text Search matching
            let matchesSearch: Bool
            if trimmedQuery.isEmpty {
                matchesSearch = true
            } else {
                let matchesName = process.name.lowercased().contains(trimmedQuery)
                let matchesPID = "\(process.id)".contains(trimmedQuery)
                let matchesBundle = process.bundleIdentifier?.lowercased().contains(trimmedQuery) ?? false
                matchesSearch = matchesName || matchesPID || matchesBundle
            }

            guard matchesSearch else { return false }

            // 2. Category matching
            switch category {
            case .all:
                return true
            case .apps:
                // Applications have a valid bundle identifier
                return process.bundleIdentifier != nil
            case .daemons:
                // Background daemons: non-apps not in system core
                let isApp = process.bundleIdentifier != nil
                return !isApp && !isSystemProcess(process)
            case .system:
                return isSystemProcess(process)
            case .highLoad:
                // High Load: CPU > 5.0% or totalMemory > 500 MB (500 * 1024 * 1024 bytes)
                return process.totalCPU > 5.0 || process.totalMemory > (500 * 1024 * 1024)
            }
        }
    }

    public static func isSystemProcess(_ process: ProcessItem) -> Bool {
        let systemNames = ["kernel_task", "launchd", "WindowServer", "syspolicyd", "macOS Sistem & Çekirdek", "macOS System & Kernel"]
        return process.id <= 1 || systemNames.contains(process.name)
    }

    public static func performAction(pid: pid_t, force: Bool) -> ProcessActionResultContract {
        guard pid > 1 else {
            return .failure("Cannot terminate system initialization process.")
        }
        let actionResult = force ? ProcessAction.forceKill(pid: pid) : ProcessAction.terminate(pid: pid)
        switch actionResult {
        case .success:
            return .success
        case .failure(let reason):
            return .failure(reason)
        }
    }
}
