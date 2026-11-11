import Foundation

/// Tachometer and operating metrics for an individual cooling fan.
public struct FanTelemetry: Identifiable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public let currentRPM: Int
    public let minRPM: Int
    public let maxRPM: Int

    public init(
        id: Int,
        name: String,
        currentRPM: Int,
        minRPM: Int = 0,
        maxRPM: Int = 6000
    ) {
        self.id = id
        self.name = name
        self.currentRPM = currentRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
    }

    /// Speed utilization percentage between minRPM and maxRPM.
    public var percentage: Double {
        guard maxRPM > minRPM else { return 0.0 }
        let clamped = min(max(currentRPM, minRPM), maxRPM)
        return Double(clamped - minRPM) / Double(maxRPM - minRPM) * 100.0
    }
}

/// Comprehensive thermal, die temperature, and cooling telemetry snapshot.
public struct ThermalMetrics: Sendable, Equatable {
    public let socDieTemperature: Double?
    public let peakDieTemperature: Double?
    public let batteryTemperature: Double?
    public let storageTemperature: Double?
    public let thermalState: ProcessInfo.ThermalState
    public let fanSpeeds: [FanTelemetry]
    public let isFanless: Bool

    public init(
        socDieTemperature: Double? = nil,
        peakDieTemperature: Double? = nil,
        batteryTemperature: Double? = nil,
        storageTemperature: Double? = nil,
        thermalState: ProcessInfo.ThermalState = .nominal,
        fanSpeeds: [FanTelemetry] = [],
        isFanless: Bool? = nil
    ) {
        self.socDieTemperature = socDieTemperature
        self.peakDieTemperature = peakDieTemperature
        self.batteryTemperature = batteryTemperature
        self.storageTemperature = storageTemperature
        self.thermalState = thermalState
        self.fanSpeeds = fanSpeeds
        self.isFanless = isFanless ?? fanSpeeds.isEmpty
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

    public var coolingStatusDescription: String {
        if isFanless {
            return "Fanless Architecture - Passive Cooling"
        } else if fanSpeeds.isEmpty {
            return "No Active Fans Detected"
        } else {
            return "\(fanSpeeds.count) Active Fans (\(fanSpeeds.map { "\($0.currentRPM) RPM" }.joined(separator: ", ")))"
        }
    }

    public static let empty = ThermalMetrics()
}
