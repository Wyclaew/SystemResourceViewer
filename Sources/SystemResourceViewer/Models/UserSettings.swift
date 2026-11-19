import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

public enum AppTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    public var id: String { rawValue }

    #if canImport(SwiftUI)
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    #endif
}

/// Persistent user settings stored in UserDefaults.
public struct UserSettings: Codable, Sendable, Equatable {
    public var refreshInterval: TimeInterval
    public var startupTab: String
    public var cpuAlertThreshold: Double
    public var cpuAlertEnabled: Bool
    public var memoryPressureAlertEnabled: Bool
    public var thermalAlertThreshold: Double
    public var thermalAlertEnabled: Bool
    public var themeOverride: AppTheme
    public var historyTimelineRange: String
    public var privacySettings: PrivacySettings

    public init(
        refreshInterval: TimeInterval = 2.0,
        startupTab: String = "Processes",
        cpuAlertThreshold: Double = 90.0,
        cpuAlertEnabled: Bool = true,
        memoryPressureAlertEnabled: Bool = true,
        thermalAlertThreshold: Double = 90.0,
        thermalAlertEnabled: Bool = true,
        themeOverride: AppTheme = .system,
        historyTimelineRange: String = "1m",
        privacySettings: PrivacySettings = .defaultSettings
    ) {
        self.refreshInterval = refreshInterval
        self.startupTab = startupTab
        self.cpuAlertThreshold = cpuAlertThreshold
        self.cpuAlertEnabled = cpuAlertEnabled
        self.memoryPressureAlertEnabled = memoryPressureAlertEnabled
        self.thermalAlertThreshold = thermalAlertThreshold
        self.thermalAlertEnabled = thermalAlertEnabled
        self.themeOverride = themeOverride
        self.historyTimelineRange = historyTimelineRange
        self.privacySettings = privacySettings
    }

    public static let defaultSettings = UserSettings()

    private static let userDefaultsKey = "com.systemresourceviewer.userSettings"

    public static func load(from defaults: UserDefaults = .standard) -> UserSettings {
        guard let data = defaults.data(forKey: userDefaultsKey),
              let settings = try? JSONDecoder().decode(UserSettings.self, from: data) else {
            return .defaultSettings
        }
        return settings
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.userDefaultsKey)
        }
    }

    public static func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: userDefaultsKey)
    }
}
