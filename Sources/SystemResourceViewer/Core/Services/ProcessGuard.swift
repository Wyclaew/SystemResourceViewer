import Darwin
import Foundation

/// Critical system process safety guard preventing termination of kernel tasks,
/// window servers, login sessions, and essential macOS infrastructure daemons.
public enum ProcessGuard: Sendable {

    /// PIDs that must NEVER be signaled under any circumstances.
    public static let blockedPIDs: Set<pid_t> = [0, 1]

    /// Critical system daemons and GUI infrastructure binaries that must not be terminated.
    public static let blockedProcessNames: Set<String> = [
        "kernel_task",
        "launchd",
        "WindowServer",
        "loginwindow",
        "diskarbitrationd",
        "opendirectoryd",
        "securityd",
        "trustd",
        "syspolicyd",
        "notifyd",
        "configd",
        "powerd",
        "fseventsd",
        "coreauthd",
        "Dock",
        "Finder",
        "SystemResourceViewer",
        "Resource Monitor"
    ]

    /// Critical macOS bundle identifiers protected from termination.
    public static let blockedBundleIdentifiers: Set<String> = [
        "com.apple.WindowServer",
        "com.apple.loginwindow",
        "com.apple.dock",
        "com.apple.finder",
        "com.apple.syspolicyd",
        "com.apple.diskarbitrationd",
        "com.apple.opendirectoryd",
        "com.apple.securityd",
        "com.apple.launchd"
    ]

    /// Protected macOS system path prefixes.
    public static let protectedPathPrefixes: [String] = [
        "/System/Library/CoreServices/",
        "/usr/libexec/",
        "/System/Library/Frameworks/",
        "/System/Library/PrivateFrameworks/",
        "/usr/sbin/"
    ]

    /// Quick boolean check whether a PID or process is protected from termination.
    public static func isProtected(
        pid: pid_t,
        name: String? = nil,
        bundleIdentifier: String? = nil,
        path: String? = nil
    ) -> Bool {
        protectionStatus(pid: pid, name: name, bundleIdentifier: bundleIdentifier, path: path).protected
    }

    /// Detailed protection evaluation for a process.
    public static func protectionStatus(
        pid: pid_t,
        name: String? = nil,
        bundleIdentifier: String? = nil,
        path: String? = nil
    ) -> (protected: Bool, reason: String?) {
        // 1. PID <= 1: Kernel idle, swapper, or launchd init process
        if pid <= 1 || blockedPIDs.contains(pid) {
            return (true, "Cannot terminate system initialization process (PID \(pid)).")
        }

        // 2. Active Application self PID check
        if pid == getpid() {
            return (true, "Cannot terminate the active Resource Monitor application directly.")
        }

        // 3. Parent Host Process check
        let ppid = getppid()
        if ppid > 1 && pid == ppid {
            return (true, "Cannot terminate parent host process (PID \(ppid)).")
        }

        // 4. Resolve name and executable path if not provided
        let resolvedName = name ?? (pid > 1 ? DarwinMachBridge.processName(for: pid) : nil)
        let resolvedPath = path ?? (pid > 1 ? DarwinMachBridge.processExecutablePath(for: pid) : nil)

        // 5. Blocked process names (case-insensitive comparison)
        if let procName = resolvedName {
            let lowercased = procName.lowercased()
            for blocked in blockedProcessNames {
                if blocked.lowercased() == lowercased {
                    return (true, "Cannot terminate critical system process '\(procName)' (PID \(pid)).")
                }
            }
        }

        // 6. Blocked bundle identifiers (case-insensitive comparison)
        if let bundleID = bundleIdentifier {
            let lowercased = bundleID.lowercased()
            for blocked in blockedBundleIdentifiers {
                if blocked.lowercased() == lowercased {
                    return (true, "Cannot terminate critical system process '\(bundleID)' (PID \(pid)).")
                }
            }
        }

        // 7. Protected system paths and components
        if let procPath = resolvedPath {
            let binaryName = URL(fileURLWithPath: procPath).lastPathComponent
            let binaryLower = binaryName.lowercased()
            let matchesBlocked = blockedProcessNames.contains { $0.lowercased() == binaryLower }

            if matchesBlocked {
                return (true, "Cannot terminate critical system process '\(binaryName)' at '\(procPath)' (PID \(pid)).")
            }

            for prefix in protectedPathPrefixes where procPath.hasPrefix(prefix) {
                if matchesBlocked ||
                    procPath.contains("WindowServer") ||
                    procPath.contains("loginwindow") ||
                    procPath.contains("Dock.app") ||
                    procPath.contains("Finder.app") ||
                    procPath.contains("diskarbitrationd") ||
                    procPath.contains("syspolicyd") ||
                    procPath.contains("opendirectoryd") {
                    return (true, "Cannot terminate protected system component at '\(procPath)' (PID \(pid)).")
                }
            }
        }

        return (false, nil)
    }
}
