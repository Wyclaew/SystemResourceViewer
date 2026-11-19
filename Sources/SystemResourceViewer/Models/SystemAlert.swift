import Foundation

public enum AlertSeverity: String, Codable, Sendable, CaseIterable {
    case info = "Info"
    case warning = "Warning"
    case critical = "Critical"

    public var systemSymbolName: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }
}

public enum AlertType: String, Codable, Sendable, CaseIterable {
    case cpuHigh = "High CPU Load"
    case memoryPressure = "Memory Pressure"
    case thermalThrottling = "Thermal Throttling"
    case diskSpaceLow = "Low Disk Space"
}

public struct SystemAlert: Identifiable, Sendable, Equatable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let type: AlertType
    public let severity: AlertSeverity
    public let title: String
    public let message: String
    public let metricValue: Double
    public let thresholdValue: Double
    public var isDismissed: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        type: AlertType,
        severity: AlertSeverity,
        title: String,
        message: String,
        metricValue: Double,
        thresholdValue: Double,
        isDismissed: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.severity = severity
        self.title = title
        self.message = message
        self.metricValue = metricValue
        self.thresholdValue = thresholdValue
        self.isDismissed = isDismissed
    }
}

public struct AlertConfiguration: Sendable, Equatable {
    public var cpuThreshold: Double
    public var cpuAlertsEnabled: Bool
    public var memoryUsageThreshold: Double
    public var memoryPressureAlertsEnabled: Bool
    public var thermalThreshold: Double
    public var thermalAlertsEnabled: Bool
    public var diskThreshold: Double
    public var diskAlertsEnabled: Bool
    public var cooldownInterval: TimeInterval

    public init(
        cpuThreshold: Double = 90.0,
        cpuAlertsEnabled: Bool = true,
        memoryUsageThreshold: Double = 90.0,
        memoryPressureAlertsEnabled: Bool = true,
        thermalThreshold: Double = 90.0,
        thermalAlertsEnabled: Bool = true,
        diskThreshold: Double = 95.0,
        diskAlertsEnabled: Bool = true,
        cooldownInterval: TimeInterval = 60.0
    ) {
        self.cpuThreshold = cpuThreshold
        self.cpuAlertsEnabled = cpuAlertsEnabled
        self.memoryUsageThreshold = memoryUsageThreshold
        self.memoryPressureAlertsEnabled = memoryPressureAlertsEnabled
        self.thermalThreshold = thermalThreshold
        self.thermalAlertsEnabled = thermalAlertsEnabled
        self.diskThreshold = diskThreshold
        self.diskAlertsEnabled = diskAlertsEnabled
        self.cooldownInterval = cooldownInterval
    }
}

public struct AlertEvaluator: Sendable {
    public static func evaluate(
        metrics: SystemMetrics,
        config: AlertConfiguration,
        lastFired: [AlertType: Date],
        now: Date = Date()
    ) -> (newAlerts: [SystemAlert], updatedFired: [AlertType: Date]) {
        var triggered: [SystemAlert] = []
        var fired = lastFired

        // 1. CPU Check
        if config.cpuAlertsEnabled && metrics.cpu.totalUsage >= config.cpuThreshold {
            let last = fired[.cpuHigh] ?? .distantPast
            if now.timeIntervalSince(last) >= config.cooldownInterval {
                let sev: AlertSeverity = metrics.cpu.totalUsage >= 95.0 ? .critical : .warning
                let alert = SystemAlert(
                    type: .cpuHigh,
                    severity: sev,
                    title: "High CPU Utilization",
                    message: String(format: "Total CPU load reached %.1f%% (threshold: %.0f%%).", metrics.cpu.totalUsage, config.cpuThreshold),
                    metricValue: metrics.cpu.totalUsage,
                    thresholdValue: config.cpuThreshold
                )
                triggered.append(alert)
                fired[.cpuHigh] = now
            }
        }

        // 2. Memory Pressure Check
        if config.memoryPressureAlertsEnabled {
            let isPressureHigh = metrics.memory.pressureLevel == .warning || metrics.memory.pressureLevel == .critical
            let isUsageHigh = metrics.memory.usedPercentage >= config.memoryUsageThreshold
            if isPressureHigh || isUsageHigh {
                let last = fired[.memoryPressure] ?? .distantPast
                if now.timeIntervalSince(last) >= config.cooldownInterval {
                    let sev: AlertSeverity = (metrics.memory.pressureLevel == .critical || metrics.memory.usedPercentage >= 95.0) ? .critical : .warning
                    let alert = SystemAlert(
                        type: .memoryPressure,
                        severity: sev,
                        title: "Memory Pressure Warning",
                        message: "Memory pressure is \(metrics.memory.pressureLevel.rawValue) (\(String(format: "%.1f%%", metrics.memory.usedPercentage)) used).",
                        metricValue: metrics.memory.usedPercentage,
                        thresholdValue: config.memoryUsageThreshold
                    )
                    triggered.append(alert)
                    fired[.memoryPressure] = now
                }
            }
        }

        // 3. Thermal Throttle Check
        if config.thermalAlertsEnabled {
            let dieTemp = metrics.thermal.socDieTemperature ?? 0.0
            let isThrottled = (metrics.thermal.socDieTemperature != nil && dieTemp >= config.thermalThreshold) ||
                              metrics.thermal.thermalState == .serious ||
                              metrics.thermal.thermalState == .critical
            if isThrottled {
                let last = fired[.thermalThrottling] ?? .distantPast
                if now.timeIntervalSince(last) >= config.cooldownInterval {
                    let sev: AlertSeverity = (dieTemp >= 95.0 || metrics.thermal.thermalState == .critical) ? .critical : .warning
                    let alert = SystemAlert(
                        type: .thermalThrottling,
                        severity: sev,
                        title: "Thermal Throttle Warning",
                        message: "SoC temperature reached \(String(format: "%.1f°C", dieTemp)) (Thermal state: \(metrics.thermal.thermalStateDescription)).",
                        metricValue: dieTemp,
                        thresholdValue: config.thermalThreshold
                    )
                    triggered.append(alert)
                    fired[.thermalThrottling] = now
                }
            }
        }

        // 4. Disk Capacity Check
        if config.diskAlertsEnabled && metrics.disk.usedPercentage >= config.diskThreshold {
            let last = fired[.diskSpaceLow] ?? .distantPast
            if now.timeIntervalSince(last) >= config.cooldownInterval {
                let alert = SystemAlert(
                    type: .diskSpaceLow,
                    severity: .warning,
                    title: "Low Disk Space",
                    message: "Volume '\(metrics.disk.volumeName)' is \(String(format: "%.1f%%", metrics.disk.usedPercentage)) full.",
                    metricValue: metrics.disk.usedPercentage,
                    thresholdValue: config.diskThreshold
                )
                triggered.append(alert)
                fired[.diskSpaceLow] = now
            }
        }

        return (triggered, fired)
    }
}
