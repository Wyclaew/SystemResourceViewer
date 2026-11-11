import Foundation

/// Thermal and battery telemetry tailored for Apple Silicon and Intel Macs.
public struct PowerMetrics: Sendable {
    public let isBatteryInstalled: Bool
    public let batteryPercentage: Int
    public let isCharging: Bool
    public let isPluggedIn: Bool
    public let cycleCount: Int?
    public let healthPercentage: Double?
    public let powerDrawWatts: Double?
    public let timeRemainingMinutes: Int?
    public let thermalState: ProcessInfo.ThermalState

    public init(
        isBatteryInstalled: Bool = false,
        batteryPercentage: Int = 100,
        isCharging: Bool = false,
        isPluggedIn: Bool = true,
        cycleCount: Int? = nil,
        healthPercentage: Double? = nil,
        powerDrawWatts: Double? = nil,
        timeRemainingMinutes: Int? = nil,
        thermalState: ProcessInfo.ThermalState = .nominal
    ) {
        self.isBatteryInstalled = isBatteryInstalled
        self.batteryPercentage = batteryPercentage
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.cycleCount = cycleCount
        self.healthPercentage = healthPercentage
        self.powerDrawWatts = powerDrawWatts
        self.timeRemainingMinutes = timeRemainingMinutes
        self.thermalState = thermalState
    }

    public var thermalStateDescription: String {
        switch thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    public var thermalStateSymbol: String {
        switch thermalState {
        case .nominal: return "flame"
        case .fair: return "flame.fill"
        case .serious: return "exclamationmark.shield.fill"
        case .critical: return "shield.slash.fill"
        @unknown default: return "questionmark"
        }
    }

    public static let empty = PowerMetrics()
}
