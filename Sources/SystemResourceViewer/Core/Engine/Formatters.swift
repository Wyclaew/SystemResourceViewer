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
}
