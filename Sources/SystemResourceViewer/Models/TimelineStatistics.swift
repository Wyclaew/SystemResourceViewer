import Foundation

/// Statistical aggregation across a slice of historical metric values.
public struct TimelineStatistics: Sendable, Equatable {
    public let min: Double
    public let mean: Double
    public let max: Double
    public let current: Double

    public init(values: [Double]) {
        if values.isEmpty {
            self.min = 0.0
            self.mean = 0.0
            self.max = 0.0
            self.current = 0.0
        } else {
            self.min = values.min() ?? 0.0
            self.max = values.max() ?? 0.0
            let sum = values.reduce(0.0, +)
            self.mean = sum / Double(values.count)
            self.current = values.last ?? 0.0
        }
    }

    public init(min: Double, mean: Double, max: Double, current: Double) {
        self.min = min
        self.mean = mean
        self.max = max
        self.current = current
    }
}
