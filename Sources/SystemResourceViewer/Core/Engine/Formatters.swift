import Foundation

/// High-performance string and metric formatting utilities.
public enum Formatters {

    /// Formats raw byte counts into human-readable binary representations (KB, MB, GB, TB).
    public static func formatBytes(_ bytes: UInt64) -> String {
        let kb = Double(bytes) / 1024.0
        let mb = kb / 1024.0
        let gb = mb / 1024.0
        let tb = gb / 1024.0

        if tb >= 1.0 {
            return String(format: "%.1f TB", tb)
        } else if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        } else if mb >= 1.0 {
            return String(format: "%.0f MB", mb)
        } else if kb >= 1.0 {
            return String(format: "%.0f KB", kb)
        } else {
            return "\(bytes) B"
        }
    }

    /// Formats transfer rate in bytes per second to auto-scaling units (B/s, KB/s, MB/s, GB/s).
    public static func formatSpeed(_ bytesPerSecond: Double) -> String {
        let kb = bytesPerSecond / 1024.0
        let mb = kb / 1024.0
        let gb = mb / 1024.0

        if gb >= 1.0 {
            return String(format: "%.1f GB/s", gb)
        } else if mb >= 1.0 {
            return String(format: "%.1f MB/s", mb)
        } else if kb >= 1.0 {
            return String(format: "%.0f KB/s", kb)
        } else {
            return String(format: "%.0f B/s", bytesPerSecond)
        }
    }

    /// Formats percentage values with a single decimal place.
    public static func formatPercentage(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    /// Formats round-trip network latency in milliseconds.
    public static func formatLatency(_ ms: Double?) -> String {
        guard let ms else { return "—" }
        return String(format: "%.0f ms", ms)
    }

    /// Formats power draw in Watts.
    public static func formatPower(_ watts: Double?) -> String {
        guard let watts else { return "—" }
        return String(format: "%.1f W", watts)
    }

    /// Formats an uptime duration in seconds to human-readable format.
    public static func formatUptime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(max(0, seconds))
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m \(secs)s"
        } else if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }

    /// Formats nanoseconds into milliseconds or seconds.
    public static func formatNanoseconds(_ ns: UInt64) -> String {
        let ms = Double(ns) / 1_000_000.0
        if ms >= 1000.0 {
            return String(format: "%.2f s", ms / 1000.0)
        } else {
            return String(format: "%.1f ms", ms)
        }
    }
}
