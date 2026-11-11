import Foundation

/// Contract for individual hardware fan tachometer
public struct FanTelemetry: Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let currentRPM: Int
    public let minRPM: Int
    public let maxRPM: Int

    public init(id: Int, name: String, currentRPM: Int, minRPM: Int = 0, maxRPM: Int = 6000) {
        self.id = id
        self.name = name
        self.currentRPM = currentRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
    }

    public var percentage: Double {
        guard maxRPM > minRPM else { return 0.0 }
        let clamped = min(maxRPM, max(minRPM, currentRPM))
        return (Double(clamped - minRPM) / Double(maxRPM - minRPM)) * 100.0
    }
}

/// Contract definition for Thermal & Fan Telemetry matching PROJECT.md § Interface Contracts
public struct ThermalMetricsContract: Sendable, Equatable {
    public let socDieTemperature: Double?
    public let peakDieTemperature: Double?
    public let batteryTemperature: Double?
    public let storageTemperature: Double?
    public let thermalState: ProcessInfo.ThermalState
    public let fanSpeeds: [FanTelemetry]

    public init(
        socDieTemperature: Double? = nil,
        peakDieTemperature: Double? = nil,
        batteryTemperature: Double? = nil,
        storageTemperature: Double? = nil,
        thermalState: ProcessInfo.ThermalState = .nominal,
        fanSpeeds: [FanTelemetry] = []
    ) {
        self.socDieTemperature = socDieTemperature
        self.peakDieTemperature = peakDieTemperature
        self.batteryTemperature = batteryTemperature
        self.storageTemperature = storageTemperature
        self.thermalState = thermalState
        self.fanSpeeds = fanSpeeds
    }

    public var isFanless: Bool {
        fanSpeeds.isEmpty
    }

    public static let empty = ThermalMetricsContract()
}
