import Charts
import SwiftUI

/// Compact sparkline graph rendered using Swift Charts with gradient area fill.
public struct MetricSparklineView: View {
    private struct DataPoint: Identifiable {
        let id: Int
        let value: Double
    }

    private let points: [DataPoint]
    private let tintColor: Color
    private let fixedMax: Double?
    private let height: CGFloat

    public init<C: Collection>(
        values: C,
        tintColor: Color = AdaptiveColor.optimal,
        fixedMax: Double? = 100.0,
        height: CGFloat = 36.0
    ) where C.Element == Double {
        self.points = values.enumerated().map { DataPoint(id: $0.offset, value: $0.element) }
        self.tintColor = tintColor
        self.fixedMax = fixedMax
        self.height = height
    }

    public var body: some View {
        Chart(points) { point in
            AreaMark(
                x: .value("Time", point.id),
                y: .value("Value", point.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [tintColor.opacity(0.32), tintColor.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Time", point.id),
                y: .value("Value", point.value)
            )
            .foregroundStyle(tintColor)
            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: 0...(fixedMax ?? (points.map(\.value).max() ?? 100.0) * 1.15 + 1.0))
        .frame(height: height)
        .animation(.easeInOut(duration: 0.25), value: points.last?.value)
    }
}
