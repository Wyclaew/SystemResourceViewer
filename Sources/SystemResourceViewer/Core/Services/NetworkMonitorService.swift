import Foundation
import Darwin
import Network

/// Actor-isolated telemetry service monitoring network bandwidth, interface routing, and latency.
public actor NetworkMonitorService {
    private let pathMonitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "com.antigravity.networkmonitor", qos: .utility)

    private var currentInterfaceType: NetworkInterfaceType = .disconnected
    private var primaryInterfaceName: String = "en0"
    private var previousSample: (inBytes: UInt64, outBytes: UInt64, time: Date)?
    private var lastMeasuredLatencyMs: Double?
    private var lastLatencyCheckTime: Date = Date()
    private var isProbingLatency: Bool = false

    /// Privacy toggle controlling whether outbound TCP socket probes to 1.1.1.1:53 are allowed.
    public var allowExternalSocketProbe: Bool = true

    public init(allowExternalSocketProbe: Bool = true) {
        self.allowExternalSocketProbe = allowExternalSocketProbe
        let monitor = NWPathMonitor()
        self.pathMonitor = monitor

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task {
                await self.updatePath(path)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        pathMonitor.cancel()
    }

    private func updatePath(_ path: NWPath) {
        if path.status == .satisfied {
            if path.usesInterfaceType(.wifi) {
                currentInterfaceType = .wifi
            } else if path.usesInterfaceType(.wiredEthernet) {
                currentInterfaceType = .ethernet
            } else if path.usesInterfaceType(.cellular) {
                currentInterfaceType = .cellular
            } else if path.usesInterfaceType(.loopback) {
                currentInterfaceType = .loopback
            } else {
                currentInterfaceType = .other
            }

            if let activeInterface = path.availableInterfaces.first {
                primaryInterfaceName = activeInterface.name
            }
        } else {
            currentInterfaceType = .disconnected
        }
    }

    /// Polls live bandwidth speeds, active IPv4 address, and measured latency.
    public func pollNetworkMetrics() async -> NetworkMetrics {
        let (currentIn, currentOut, ipv4) = fetchInterfaceBytesAndIPv4(targetInterface: primaryInterfaceName)
        let now = Date()

        var rxSpeed = 0.0
        var txSpeed = 0.0

        if let prev = previousSample {
            let dt = now.timeIntervalSince(prev.time)
            if dt > 0.05 {
                let dIn = currentIn >= prev.inBytes ? currentIn - prev.inBytes : 0
                let dOut = currentOut >= prev.outBytes ? currentOut - prev.outBytes : 0
                rxSpeed = Double(dIn) / dt
                txSpeed = Double(dOut) / dt
            }
        }

        previousSample = (inBytes: currentIn, outBytes: currentOut, time: now)

        // Measure network latency every 5 seconds asynchronously in background to avoid blocking polling ticks
        if allowExternalSocketProbe && currentInterfaceType != .disconnected && now.timeIntervalSince(lastLatencyCheckTime) >= 5.0 && !isProbingLatency {
            lastLatencyCheckTime = now
            isProbingLatency = true
            Task { [weak self] in
                guard let self else { return }
                let latency = await self.probeLatency()
                await self.recordLatency(latency)
            }
        }

        return NetworkMetrics(
            downloadBytesPerSecond: rxSpeed,
            uploadBytesPerSecond: txSpeed,
            primaryInterfaceName: primaryInterfaceName,
            interfaceType: currentInterfaceType,
            localIPv4: ipv4 ?? "—",
            latencyMilliseconds: allowExternalSocketProbe ? lastMeasuredLatencyMs : nil
        )
    }

    /// Dynamically enables or disables external socket probing.
    public func setAllowExternalSocketProbe(_ allowed: Bool) {
        self.allowExternalSocketProbe = allowed
        if !allowed {
            self.lastMeasuredLatencyMs = nil
        }
    }

    private func recordLatency(_ latency: Double?) {
        guard allowExternalSocketProbe else {
            self.lastMeasuredLatencyMs = nil
            self.isProbingLatency = false
            return
        }
        self.lastMeasuredLatencyMs = latency
        self.isProbingLatency = false
    }

    // MARK: - Low-Level getifaddrs Reader

    private func fetchInterfaceBytesAndIPv4(targetInterface: String) -> (inBytes: UInt64, outBytes: UInt64, ipv4: String?) {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else {
            return (0, 0, nil)
        }
        defer {
            freeifaddrs(ifaddrPtr)
        }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var primaryIPv4: String?
        var fallbackIPv4: String?

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let ifa = current.pointee
            let flags = Int32(ifa.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isRunning = (flags & IFF_RUNNING) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            guard isUp, isRunning, !isLoopback else {
                ptr = ifa.ifa_next
                continue
            }

            let name = String(cString: ifa.ifa_name)

            if let addr = ifa.ifa_addr {
                let family = addr.pointee.sa_family

                // Extract hardware interface packet statistics
                if family == UInt8(AF_LINK), let data = ifa.ifa_data {
                    let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                    totalIn += UInt64(ifData.ifi_ibytes)
                    totalOut += UInt64(ifData.ifi_obytes)
                }

                // Extract IPv4 address
                if family == UInt8(AF_INET) {
                    var sin = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    if inet_ntop(AF_INET, &sin.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                        let clean = buffer.map { UInt8(bitPattern: $0) }.prefix(while: { $0 != 0 })
                        let ip = String(decoding: clean, as: UTF8.self)
                        if name == targetInterface {
                            primaryIPv4 = ip
                        } else if fallbackIPv4 == nil {
                            fallbackIPv4 = ip
                        }
                    }
                }
            }

            ptr = ifa.ifa_next
        }

        return (totalIn, totalOut, primaryIPv4 ?? fallbackIPv4)
    }

    // MARK: - Lightweight Latency Socket Probe

    private func probeLatency() async -> Double? {
        // Measure TCP handshake latency to 1.1.1.1:53 with a 1-second timeout
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let start = DispatchTime.now()
                let sock = socket(AF_INET, SOCK_STREAM, 0)
                guard sock >= 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                defer {
                    close(sock)
                }

                // Set non-blocking
                let flags = fcntl(sock, F_GETFL, 0)
                _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = UInt16(53).bigEndian
                _ = inet_pton(AF_INET, "1.1.1.1", &addr.sin_addr)

                let connectRes = withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        connect(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }

                if connectRes == 0 {
                    let elapsedNs = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                    let ms = Double(elapsedNs) / 1_000_000.0
                    continuation.resume(returning: Double(round(ms * 10.0) / 10.0))
                    return
                }

                if errno == EINPROGRESS {
                    var pollFd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
                    let pollRes = poll(&pollFd, 1, 800) // 800ms timeout
                    if pollRes > 0 && (pollFd.revents & Int16(POLLOUT)) != 0 {
                        var socketError: Int32 = 0
                        var len = socklen_t(MemoryLayout<Int32>.size)
                        if getsockopt(sock, SOL_SOCKET, SO_ERROR, &socketError, &len) == 0 && socketError == 0 {
                            let elapsedNs = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                            let ms = Double(elapsedNs) / 1_000_000.0
                            continuation.resume(returning: Double(round(ms * 10.0) / 10.0))
                            return
                        }
                    }
                }

                continuation.resume(returning: nil)
            }
        }
    }
}
