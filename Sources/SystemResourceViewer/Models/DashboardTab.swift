import Foundation

/// Unified main window tabs.
public enum DashboardTab: String, CaseIterable, Identifiable, Codable, Sendable {
    case processes = "Processes"
    case diagnostics = "Diagnostics"
    case history = "History"
    case systemProfile = "System Profile"

    public var id: String { rawValue }

    public var systemImage: String {
        switch self {
        case .processes: return "list.bullet.rectangle"
        case .diagnostics: return "gauge.with.dots.needle.bottom.50percent"
        case .history: return "chart.xyaxis.line"
        case .systemProfile: return "desktopcomputer"
        }
    }
}
