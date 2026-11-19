import Charts
import SwiftUI

/// Multi-timeline historical resource telemetry charts with interactive hover scrubbing.
public struct HistoryView: View {
    @ObservedObject var viewModel: DashboardViewModel

    public init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
    }

    private var range: HistoryTimelineRange {
        viewModel.selectedHistoryRange
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Top Range Picker Bar
                HStack {
                    Text("Historical Telemetry")
                        .font(.system(size: 16, weight: .bold))

                    Spacer()

                    Picker("Timeline", selection: $viewModel.selectedHistoryRange) {
                        ForEach(HistoryTimelineRange.allCases) { r in
                            Text(r.label).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }
                .padding(.horizontal, 4)

                // 1. CPU History Chart
                let cpuValues = viewModel.historySlice(for: viewModel.cpuHistory15m, range: range)
                historyCard(
                    title: "CPU Utilization",
                    icon: "cpu",
                    unit: "%",
                    values: cpuValues,
                    color: AdaptiveColor.pCore,
                    fixedMax: 100.0
                )

                // 2. GPU History Chart
                let gpuValues = viewModel.historySlice(for: viewModel.gpuHistory15m, range: range)
                historyCard(
                    title: "GPU Utilization",
                    icon: "display",
                    unit: "%",
                    values: gpuValues,
                    color: Color.purple,
                    fixedMax: 100.0
                )

                // 3. Memory History Chart
                let memValues = viewModel.historySlice(for: viewModel.memoryHistory15m, range: range)
                historyCard(
                    title: "Memory Pressure & Usage",
                    icon: "memorychip",
                    unit: "%",
                    values: memValues,
                    color: AdaptiveColor.moderate,
                    fixedMax: 100.0
                )

                // 4. Network Throughput Chart
                let netValues = viewModel.historySlice(for: viewModel.downloadSpeedHistory15m, range: range)
                historyCard(
                    title: "Network Download Speed",
                    icon: "arrow.down.circle",
                    unit: "B/s",
                    values: netValues,
                    color: AdaptiveColor.optimal,
                    isSpeed: true
                )

                // 5. Disk Read Throughput Chart
                let diskValues = viewModel.historySlice(for: viewModel.diskReadHistory15m, range: range)
                historyCard(
                    title: "Storage Read Throughput",
                    icon: "internaldrive",
                    unit: "B/s",
                    values: diskValues,
                    color: Color.cyan,
                    isSpeed: true
                )
            }
            .padding(16)
        }
    }

    private func historyCard(
        title: String,
        icon: String,
        unit: String,
        values: [Double],
        color: Color,
        fixedMax: Double? = nil,
        isSpeed: Bool = false
    ) -> some View {
        let stats = TimelineStatistics(values: values)
        return InteractiveHistoryChart(
            title: title,
            icon: icon,
            unit: unit,
            values: values,
            stats: stats,
            color: color,
            fixedMax: fixedMax,
            isSpeed: isSpeed,
            range: range
        )
    }
}

/// Standalone interactive chart with hover scrubbing, point marks, and statistical aggregation.
struct InteractiveHistoryChart: View {
    let title: String
    let icon: String
    let unit: String
    let values: [Double]
    let stats: TimelineStatistics
    let color: Color
    let fixedMax: Double?
    let isSpeed: Bool
    let range: HistoryTimelineRange

    @State private var hoveredIndex: Int?

    private struct ChartPoint: Identifiable {
        let id: Int
        let index: Int
        let value: Double
    }

    private var points: [ChartPoint] {
        values.enumerated().map { ChartPoint(id: $0.offset, index: $0.offset, value: $0.element) }
    }

    private func formatValue(_ val: Double) -> String {
        if isSpeed {
            return Formatters.formatSpeed(val)
        } else if unit == "%" {
            return String(format: "%.1f%%", val)
        } else {
            return String(format: "%.1f %@", val, unit)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .bold))

                Spacer()

                if let idx = hoveredIndex, idx >= 0, idx < values.count {
                    let offsetSeconds = (values.count - 1 - idx) * (range == .fifteenMinutes ? 1 : 1)
                    Text("T - \(offsetSeconds)s: \(formatValue(values[idx]))")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color)
                } else {
                    Text("Current: \(formatValue(stats.current))")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }

            // Chart
            Chart {
                ForEach(points) { pt in
                    AreaMark(
                        x: .value("Sample", pt.index),
                        y: .value("Value", pt.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color.opacity(0.35), color.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Sample", pt.index),
                        y: .value("Value", pt.value)
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }

                if let idx = hoveredIndex, idx >= 0, idx < values.count {
                    RuleMark(x: .value("Selected", idx))
                        .foregroundStyle(Color.primary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    PointMark(
                        x: .value("Selected", idx),
                        y: .value("Value", values[idx])
                    )
                    .symbolSize(36)
                    .foregroundStyle(color)
                }
            }
            .chartXAxis(.hidden)
            .chartLegend(.hidden)
            .chartYScale(domain: 0...(fixedMax ?? (values.max().map { max($0 * 1.15, 1.0) } ?? 100.0)))
            .frame(height: 120)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let plotFrame = proxy.plotFrame.map { geo[$0] } ?? geo.frame(in: .local)
                                guard plotFrame.contains(location) else {
                                    self.hoveredIndex = nil
                                    return
                                }
                                let xPosition = location.x - plotFrame.origin.x
                                if let indexValue: Int = proxy.value(atX: xPosition) {
                                    self.hoveredIndex = max(0, min(values.count - 1, indexValue))
                                }
                            case .ended:
                                self.hoveredIndex = nil
                            }
                        }
                }
            }

            Divider()

            // Statistics Bar
            HStack(spacing: 20) {
                statPill(label: "Min", value: formatValue(stats.min))
                statPill(label: "Mean", value: formatValue(stats.mean))
                statPill(label: "Max", value: formatValue(stats.max))
                statPill(label: "Current", value: formatValue(stats.current))
                Spacer()
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func statPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }
}
