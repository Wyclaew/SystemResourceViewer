import SwiftUI

/// Horizontal bar representing real-time load for a single CPU core, differentiating P and E cores.
public struct CoreUsageBarView: View {
    private let core: CoreUsage
    private let displayNumber: Int

    public init(core: CoreUsage, displayNumber: Int) {
        self.core = core
        self.displayNumber = displayNumber
    }

    private var badgeColor: Color {
        core.type == .performance ? AdaptiveColor.pCore : AdaptiveColor.eCore
    }

    private var barColor: Color {
        AdaptiveColor.forPercentage(core.totalUsage)
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Core identification badge
            HStack(spacing: 2) {
                Text(core.type.shortLabel)
                    .font(.system(size: 10, weight: .bold))
                Text("\(displayNumber)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .frame(width: 32, alignment: .center)

            // Usage progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.08))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [barColor.opacity(0.85), barColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(core.totalUsage / 100.0))))
                        .animation(.easeInOut(duration: 0.2), value: core.totalUsage)
                }
            }
            .frame(height: 6)

            // Monospaced percentage label
            Text(String(format: "%3.0f%%", core.totalUsage))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }
}
