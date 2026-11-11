import Foundation

/// Actor-isolated telemetry service monitoring Apple Silicon die sensors, battery/storage thermals, and fan speeds.
public actor ThermalMonitorService {
    private let hidClient: IOHIDBridge.ClientWrapper?
    private let isFanlessPlatform: Bool

    public init() {
        self.hidClient = IOHIDBridge.ClientWrapper()
        self.isFanlessPlatform = IOKitBridge.isFanlessArchitecture()
    }

    /// Polls live thermal sensors and fan tachometers.
    public func pollThermalMetrics() -> ThermalMetrics {
        let snapshot = hidClient?.sample()
        let fanTelemetry = IOKitBridge.fetchFanTelemetry()
        let thermalState = ProcessInfo.processInfo.thermalState

        let isFanless = isFanlessPlatform || fanTelemetry.isFanless

        return ThermalMetrics(
            socDieTemperature: snapshot?.socDieAverageTemperature,
            peakDieTemperature: snapshot?.socDiePeakTemperature,
            batteryTemperature: snapshot?.batteryTemperature,
            storageTemperature: snapshot?.storageTemperature,
            thermalState: thermalState,
            fanSpeeds: fanTelemetry.fans,
            isFanless: isFanless
        )
    }
}
