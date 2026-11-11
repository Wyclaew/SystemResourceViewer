import SwiftUI

/// Detailed Battery, Power Draw, and Thermal State card for Apple Silicon Macs.
public struct PowerDashboardSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    private let isCompact: Bool

    public init(viewModel: DashboardViewModel, isCompact: Bool = false) {
        self.viewModel = viewModel
        self.isCompact = isCompact
    }

    private var power: PowerMetrics {
        viewModel.metrics.power
    }

    public var body: some View {
        CardContainer {
            // Header
            SectionHeaderView(
                title: power.isBatteryInstalled ? "Battery & Power" : "Power & Thermals",
                symbol: power.isBatteryInstalled ? "bolt.batteryblock.fill" : "powerplug.fill",
                symbolColor: AdaptiveColor.forThermalState(power.thermalState)
            ) {
                // Thermal state badge
                HStack(spacing: 4) {
                    Image(systemName: power.thermalStateSymbol)
                        .font(.system(size: 11))
                    Text(power.thermalStateDescription)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(AdaptiveColor.forThermalState(power.thermalState))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AdaptiveColor.forThermalState(power.thermalState).opacity(0.12))
                .clipShape(Capsule())
            }

            if power.isBatteryInstalled {
                // Laptop Battery Layout
                HStack(spacing: 14) {
                    MetricRingGauge(
                        percentage: Double(power.batteryPercentage),
                        title: power.isCharging ? "CHG" : "BAT",
                        size: isCompact ? 56 : 64,
                        lineWidth: 6,
                        overrideColor: power.isCharging ? AdaptiveColor.optimal : AdaptiveColor.forPercentage(Double(100 - power.batteryPercentage))
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("State:")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(power.isCharging ? "Charging" : (power.isPluggedIn ? "AC Power" : "On Battery"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primary)
                        }

                        if let watts = power.powerDrawWatts {
                            HStack {
                                Text("Power Draw:")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Formatters.formatPower(watts))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundStyle(AdaptiveColor.forPercentage(watts * 2.0))
                            }
                        }

                        if let minutes = power.timeRemainingMinutes {
                            HStack {
                                Text(power.isCharging ? "To Full:" : "Remaining:")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(minutes / 60)h \(minutes % 60)m")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .monospacedDigit()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Cycle count and Health block
                    VStack(alignment: .trailing, spacing: 3) {
                        if let cycles = power.cycleCount {
                            HStack(spacing: 4) {
                                Text("Cycles:")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text("\(cycles)")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .monospacedDigit()
                            }
                        }

                        if let health = power.healthPercentage {
                            HStack(spacing: 4) {
                                Text("Health:")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text("\(Int(round(health)))%")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundStyle(AdaptiveColor.forPercentage(Double(100 - Int(health))))
                            }
                        }
                    }
                    .frame(width: 80, alignment: .trailing)
                }
            } else {
                // Desktop Mac (Mac Studio / Mac mini / Mac Pro)
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 52, height: 52)
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Connected to AC Power")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Desktop Apple Silicon Architecture")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Thermal Status")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(power.thermalStateDescription)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AdaptiveColor.forThermalState(power.thermalState))
                    }
                }
            }
        }
    }
}
