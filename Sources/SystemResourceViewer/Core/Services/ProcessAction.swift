import AppKit
import Darwin
import Foundation

/// Outcome of a process termination action.
public enum ProcessActionResult: Sendable, Equatable {
    case success
    case failure(String)
}

/// Provides safe process control routines (SIGTERM, SIGKILL, Reveal in Finder).
public enum ProcessAction {

    /// Sends SIGTERM to allow graceful process termination, returning detailed result.
    @discardableResult
    public static func terminate(pid: pid_t) -> ProcessActionResult {
        guard pid > 1 else {
            return .failure("Cannot terminate system initialization process (PID \(pid)).")
        }
        guard pid != getpid() else {
            return .failure("Cannot terminate the active Resource Monitor application directly.")
        }
        if Darwin.kill(pid, SIGTERM) == 0 {
            return .success
        }
        return mapKillError(errno, pid: pid, signalName: "SIGTERM")
    }

    /// Sends SIGKILL to immediately force-terminate an unresponsive process, returning detailed result.
    @discardableResult
    public static func forceKill(pid: pid_t) -> ProcessActionResult {
        guard pid > 1 else {
            return .failure("Cannot terminate system initialization process (PID \(pid)).")
        }
        guard pid != getpid() else {
            return .failure("Cannot terminate the active Resource Monitor application directly.")
        }
        if Darwin.kill(pid, SIGKILL) == 0 {
            return .success
        }
        return mapKillError(errno, pid: pid, signalName: "SIGKILL")
    }

    /// Maps POSIX errno to a clear, actionable failure reason.
    private static func mapKillError(_ err: Int32, pid: pid_t, signalName: String) -> ProcessActionResult {
        switch err {
        case EPERM:
            return .failure("Operation not permitted (EPERM). Process \(pid) is owned by another user or macOS system.")
        case ESRCH:
            return .failure("No such process (ESRCH). Process \(pid) has already terminated.")
        case EINVAL:
            return .failure("Invalid signal (\(signalName)) specified.")
        default:
            let errorString = String(cString: strerror(err))
            return .failure("Termination failed (Error \(err): \(errorString)).")
        }
    }

    /// Reveals the executable binary for the given process in Finder.
    public static func revealInFinder(pid: pid_t) {
        guard let path = DarwinMachBridge.processExecutablePath(for: pid) else { return }
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    /// Copies the process PID or diagnostic info to the macOS clipboard.
    public static func copyPIDToClipboard(pid: pid_t) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("\(pid)", forType: .string)
    }
}
