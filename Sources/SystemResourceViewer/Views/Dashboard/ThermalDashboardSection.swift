import SwiftUI

/// Dedicated dashboard telemetry card for multi-channel temperatures and fan tachometers.
public struct ThermalDashboardSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    private let isCompact: Bool

    public init(viewModel: DashboardViewModel, isCompact: Bool = false) {
        self.viewModel = viewModel
        self.isCompact = isCompact
    }

    private var thermal: ThermalMetrics {
        viewModel.metrics.thermal
    }

    public var body: some View {
        CardContainer {
            // Header
            SectionHeaderView(
                title: "Thermals & Cooling",
                symbol: "thermometer.medium",
                symbolColor: AdaptiveColor.forThermalState(thermal.thermalState)
            ) {
                // Thermal state badge
                HStack(spacing: 4) {
                    Image(systemName: thermal.thermalStateSymbol)
                        .font(.system(size: 11))
                    Text(thermal.thermalStateDescription)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(AdaptiveColor.forThermalState(thermal.thermalState))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AdaptiveColor.forThermalState(thermal.thermalState).opacity(0.12))
                .clipShape(Capsule())
            }

            // Top Row: Multi-Channel Temperature Readouts
            HStack(spacing: isCompact ? 10 : 16) {
                // SoC Die Average Gauge
                let avgTemp = thermal.socDieTemperature ?? 0.0
                MetricRingGauge(
                    percentage: min(100.0, (avgTemp / 100.0) * 100.0),
                    title: avgTemp > 0 ? "\(Int(round(avgTemp)))°" : "--",
                    size: isCompact ? 52 : 60,
                    lineWidth: 5,
                    overrideColor: temperatureColor(avgTemp)
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text("SoC Die Average")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)

                    if let avg = thermal.socDieTemperature {
                        Text(String(format: "%.1f °C", avg))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(temperatureColor(avg))
                    } else {
                        Text("Nominal (Fallback)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    if let peak = thermal.peakDieTemperature {
                        Text("Peak: \(String(format: "%.1f °C", peak))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 4)

                // Secondary Sensors (Battery & Storage)
                VStack(alignment: .trailing, spacing: 4) {
                    if let bat = thermal.batteryTemperature {
                        HStack(spacing: 4) {
                            Text("Battery:")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f °C", bat))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                        }
                    }

                    if let storage = thermal.storageTemperature {
                        HStack(spacing: 4) {
                            Text("Storage:")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f °C", storage))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                        }
                    }
                }
            }

            Divider().opacity(0.6)

            // Bottom Section: Cooling Architecture (Passive vs Fan Tachometers)
            if thermal.isFanless {
                // Intelligent Passive Cooling Display
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.teal.opacity(0.12))
                            .frame(width: 38, height: 38)
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.teal)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fanless Architecture")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Passive Cooling • Silent Operation")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("0 RPM")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(Capsule())
                }
                .padding(.vertical, 2)
            } else if !thermal.fanSpeeds.isEmpty {
                // Fan Tachometer Rows
                VStack(spacing: 8) {
                    ForEach(thermal.fanSpeeds) { fan in
                        HStack(spacing: 10) {
                            Image(systemName: "fanblades.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(fanColor(fan))

                            Text(fan.name)
                                .font(.system(size: 11, weight: .medium))

                            Spacer()

                            Text("\(fan.currentRPM) RPM")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(fanColor(fan))

                            Text("(\(fan.minRPM)-\(fan.maxRPM))")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } else {
                HStack {
                    Text("No Active Fan Sensors Detected")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    private func temperatureColor(_ celsius: Double) -> Color {
        if celsius <= 0 { return .secondary }
        if celsius < 55.0 { return AdaptiveColor.optimal }
        if celsius < 75.0 { return AdaptiveColor.moderate }
        if celsius < 90.0 { return .orange }
        return AdaptiveColor.critical
    }

    private func fanColor(_ fan: FanTelemetry) -> Color {
        if fan.percentage < 40.0 { return AdaptiveColor.optimal }
        if fan.percentage < 75.0 { return AdaptiveColor.moderate }
        return AdaptiveColor.critical
    }
}
