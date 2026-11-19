import Foundation

/// Supported historical telemetry timelines for charts.
public enum HistoryTimelineRange: String, CaseIterable, Identifiable, Codable, Sendable {
    case oneMinute = "1m"
    case fiveMinutes = "5m"
    case fifteenMinutes = "15m"

    public var id: String { rawValue }

    public var sampleCount: Int {
        switch self {
        case .oneMinute: return 60
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        }
    }

    public var label: String {
        switch self {
        case .oneMinute: return "1 Minute"
        case .fiveMinutes: return "5 Minutes"
        case .fifteenMinutes: return "15 Minutes"
        }
    }
}
