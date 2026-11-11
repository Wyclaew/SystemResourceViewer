import Foundation

/// Active network interface classification.
public enum NetworkInterfaceType: String, Sendable {
    case wifi = "Wi-Fi"
    case ethernet = "Ethernet"
    case cellular = "Cellular"
    case loopback = "Loopback"
    case other = "Other"
    case disconnected = "Offline"

    public var systemSymbolName: String {
        switch self {
        case .wifi: return "wifi"
        case .ethernet: return "cable.connector"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .loopback: return "arrow.triangle.2.circlepath"
        case .other: return "network"
        case .disconnected: return "wifi.slash"
        }
    }
}

/// Real-time network throughput and connectivity status.
public struct NetworkMetrics: Sendable {
    public let downloadBytesPerSecond: Double
    public let uploadBytesPerSecond: Double
    public let primaryInterfaceName: String
    public let interfaceType: NetworkInterfaceType
    public let localIPv4: String
    public let latencyMilliseconds: Double?

    public init(
        downloadBytesPerSecond: Double = 0.0,
        uploadBytesPerSecond: Double = 0.0,
        primaryInterfaceName: String = "en0",
        interfaceType: NetworkInterfaceType = .disconnected,
        localIPv4: String = "—",
        latencyMilliseconds: Double? = nil
    ) {
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.primaryInterfaceName = primaryInterfaceName
        self.interfaceType = interfaceType
        self.localIPv4 = localIPv4
        self.latencyMilliseconds = latencyMilliseconds
    }

    public static let empty = NetworkMetrics()
}
