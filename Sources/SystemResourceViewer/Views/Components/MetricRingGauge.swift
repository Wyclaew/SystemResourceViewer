import SwiftUI

/// Circular progress ring gauge with monospaced center readout and adaptive semantic coloring.
public struct MetricRingGauge: View {
    private let percentage: Double
    private let title: String?
    private let size: CGFloat
    private let lineWidth: CGFloat
    private let overrideColor: Color?

    public init(
        percentage: Double,
        title: String? = nil,
        size: CGFloat = 64.0,
        lineWidth: CGFloat = 6.0,
        overrideColor: Color? = nil
    ) {
        let safePercentage = percentage.isFinite ? min(100.0, max(0.0, percentage)) : 0.0
        self.percentage = safePercentage
        self.title = title
        self.size = size
        self.lineWidth = lineWidth
        self.overrideColor = overrideColor
    }

    private var activeColor: Color {
        overrideColor ?? AdaptiveColor.forPercentage(percentage)
    }

    private var displayPercentage: Int {
        percentage.isFinite ? Int(round(percentage)) : 0
    }

    public var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)

            // Foreground progress arc
            Circle()
                .trim(from: 0.0, to: CGFloat(percentage / 100.0))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [activeColor.opacity(0.85), activeColor]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: percentage)

            // Center metric text
            VStack(spacing: 0) {
                Text("\(displayPercentage)%")
                    .font(.system(size: size * 0.26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                if let title {
                    Text(title)
                        .font(.system(size: size * 0.14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.map { "\($0) gauge" } ?? "Metric gauge")
        .accessibilityValue("\(displayPercentage) percent")
    }
}
