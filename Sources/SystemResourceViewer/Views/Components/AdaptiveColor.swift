import SwiftUI

/// Semantic adaptive colors for system health and load visualization.
public enum AdaptiveColor {
    public static let optimal = Color(red: 0.18, green: 0.80, blue: 0.44) // Vibrant Emerald Green
    public static let moderate = Color(red: 1.0, green: 0.65, blue: 0.0) // Amber / Orange
    public static let critical = Color(red: 1.0, green: 0.30, blue: 0.30) // Coral Red

    public static let pCore = Color(red: 0.35, green: 0.55, blue: 1.0) // High-performance Electric Blue
    public static let eCore = Color(red: 0.20, green: 0.78, blue: 0.65) // Energy-efficient Cyan / Mint

    /// Resolves color based on percentage threshold (0 - 100).
    public static func forPercentage(_ value: Double) -> Color {
        if value < 60.0 {
            return optimal
        } else if value < 85.0 {
            return moderate
        } else {
            return critical
        }
    }

    /// Resolves color based on memory pressure.
    public static func forPressure(_ level: MemoryPressureLevel) -> Color {
        switch level {
        case .normal: return optimal
        case .warning: return moderate
        case .critical: return critical
        }
    }

    /// Resolves color based on thermal state.
    public static func forThermalState(_ state: ProcessInfo.ThermalState) -> Color {
        switch state {
        case .nominal: return optimal
        case .fair: return moderate
        case .serious, .critical: return critical
        @unknown default: return optimal
        }
    }
}
