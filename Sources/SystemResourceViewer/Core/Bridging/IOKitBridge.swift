import Foundation
import IOKit
import IOKit.ps

/// Low-level IOKit bridging for disk storage controllers and Apple power subsystems.
public enum IOKitBridge {

    // MARK: - Disk Storage I/O

    public struct DiskIOBytes: Sendable {
        public let readBytes: UInt64
        public let writeBytes: UInt64

        public init(readBytes: UInt64, writeBytes: UInt64) {
            self.readBytes = readBytes
            self.writeBytes = writeBytes
        }
    }

    /// Fetches cumulative read and write bytes reported by IOBlockStorageDriver.
    public static func fetchCumulativeDiskIOBytes() -> DiskIOBytes? {
        var iterator: io_iterator_t = 0
        let matchDict = IOServiceMatching("IOBlockStorageDriver")
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iterator)

        guard kr == KERN_SUCCESS else {
            return nil
        }

        defer {
            IOObjectRelease(iterator)
        }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0
        var foundAny = false

        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let statsCF = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0),
               let stats = statsCF.takeRetainedValue() as? [String: Any] {
                let parsed = parseDiskIOStats(from: stats)
                if let read = parsed.read {
                    totalRead += read
                    foundAny = true
                }
                if let write = parsed.write {
                    totalWrite += write
                    foundAny = true
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        return foundAny ? DiskIOBytes(readBytes: totalRead, writeBytes: totalWrite) : nil
    }

    /// Safely parses cumulative read and write bytes from an IOBlockStorageDriver Statistics dictionary,
    /// resilient against __NSCFNumber and Int64 bridging variations.
    public static func parseDiskIOStats(from stats: [String: Any]) -> (read: UInt64?, write: UInt64?) {
        let read = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? (stats["Bytes (Read)"] as? Int64).map { UInt64(max(0, $0)) }
        let write = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? (stats["Bytes (Write)"] as? Int64).map { UInt64(max(0, $0)) }
        return (read, write)
    }

    // MARK: - Power & Battery Telemetry

    public struct BatteryDetails: Sendable {
        public let isPresent: Bool
        public let currentCapacity: Int
        public let maxCapacity: Int
        public let isCharging: Bool
        public let isPluggedIn: Bool
        public let cycleCount: Int?
        public let healthPercentage: Double?
        public let powerDrawWatts: Double?
        public let timeRemainingMinutes: Int?
    }

    /// Fetches live power and battery telemetry.
    public static func fetchBatteryTelemetry() -> BatteryDetails {
        var isPresent = false
        var currentCap = 100
        var maxCap = 100
        var isCharging = false
        var isPluggedIn = true
        var timeRemaining: Int?

        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
                    if let type = desc[kIOPSTypeKey as String] as? String, type == (kIOPSInternalBatteryType as String) {
                        isPresent = (desc[kIOPSIsPresentKey as String] as? Bool) ?? true
                        currentCap = (desc[kIOPSCurrentCapacityKey as String] as? Int) ?? 100
                        maxCap = (desc[kIOPSMaxCapacityKey as String] as? Int) ?? 100
                        isCharging = (desc[kIOPSIsChargingKey as String] as? Bool) ?? false

                        if let state = desc[kIOPSPowerSourceStateKey as String] as? String {
                            isPluggedIn = (state == (kIOPSACPowerValue as String))
                        }

                        if let minutes = desc[kIOPSTimeToEmptyKey as String] as? Int, minutes > 0 {
                            timeRemaining = minutes
                        } else if let minutes = desc[kIOPSTimeToFullChargeKey as String] as? Int, minutes > 0 {
                            timeRemaining = minutes
                        }
                    }
                }
            }
        }

        // Query AppleSmartBattery for deep hardware statistics (cycle count, wattage, health)
        var cycleCount: Int?
        var healthPercentage: Double?
        var powerDrawWatts: Double?

        var iter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"), &iter) == KERN_SUCCESS {
            let service = IOIteratorNext(iter)
            if service != 0 {
                var props: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let dict = props?.takeRetainedValue() as? [String: Any] {
                    let parsed = parseBatteryProperties(from: dict)
                    cycleCount = parsed.cycleCount
                    healthPercentage = parsed.healthPercentage
                    powerDrawWatts = parsed.powerDrawWatts
                }
                IOObjectRelease(service)
            }
            IOObjectRelease(iter)
        }

        return BatteryDetails(
            isPresent: isPresent,
            currentCapacity: currentCap,
            maxCapacity: maxCap,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            cycleCount: cycleCount,
            healthPercentage: healthPercentage,
            powerDrawWatts: powerDrawWatts,
            timeRemainingMinutes: timeRemaining
        )
    }

    /// Safely parses cycle count, health percentage, and power draw in Watts from an AppleSmartBattery dictionary,
    /// resilient against __NSCFNumber and Double bridging variations.
    public static func parseBatteryProperties(from dict: [String: Any]) -> (cycleCount: Int?, healthPercentage: Double?, powerDrawWatts: Double?) {
        let cycleCount = (dict["CycleCount"] as? NSNumber)?.intValue ?? (dict["CycleCount"] as? Int)

        var healthPercentage: Double?
        let maxCapacity = (dict["MaxCapacity"] as? NSNumber)?.doubleValue ?? (dict["MaxCapacity"] as? Double)
        let designCapacity = (dict["DesignCapacity"] as? NSNumber)?.doubleValue ?? (dict["DesignCapacity"] as? Double)

        if let maxCap = maxCapacity, let designCap = designCapacity, designCap > 0 {
            healthPercentage = min(100.0, Swift.max(0.0, (maxCap / designCap) * 100.0))
        } else if let maxCap = maxCapacity {
            healthPercentage = min(100.0, maxCap)
        }

        var powerDrawWatts: Double?
        // Power calculation in Watts:
        // InstantAmperage in mA, Voltage in mV -> (mA * mV) / 1,000,000 = Watts
        let amperage = (dict["InstantAmperage"] as? NSNumber)?.doubleValue ?? (dict["Amperage"] as? NSNumber)?.doubleValue ?? (dict["InstantAmperage"] as? Double) ?? (dict["Amperage"] as? Double)
        let voltage = (dict["Voltage"] as? NSNumber)?.doubleValue ?? (dict["Voltage"] as? Double)
        if let amp = amperage, let volt = voltage, volt > 0 {
            let watts = abs(amp * volt) / 1_000_000.0
            powerDrawWatts = Double(round(watts * 10.0) / 10.0)
        }

        return (cycleCount, healthPercentage, powerDrawWatts)
    }

    // MARK: - GPU Hardware & Utilization Telemetry

    public struct GPUHardwareDetails: Sendable, Equatable {
        public let modelName: String
        public let coreCount: Int
        public let deviceUtilization: Double       // 0.0 ... 100.0%
        public let rendererUtilization: Double     // 0.0 ... 100.0%
        public let tilerUtilization: Double        // 0.0 ... 100.0%
        public let allocatedVRAMBytes: UInt64
        public let inUseVRAMBytes: UInt64
        public let hasUnifiedMemory: Bool

        public init(
            modelName: String = "Apple Silicon GPU",
            coreCount: Int = 0,
            deviceUtilization: Double = 0.0,
            rendererUtilization: Double = 0.0,
            tilerUtilization: Double = 0.0,
            allocatedVRAMBytes: UInt64 = 0,
            inUseVRAMBytes: UInt64 = 0,
            hasUnifiedMemory: Bool = true
        ) {
            self.modelName = modelName
            self.coreCount = coreCount
            self.deviceUtilization = deviceUtilization
            self.rendererUtilization = rendererUtilization
            self.tilerUtilization = tilerUtilization
            self.allocatedVRAMBytes = allocatedVRAMBytes
            self.inUseVRAMBytes = inUseVRAMBytes
            self.hasUnifiedMemory = hasUnifiedMemory
        }

        public static let empty = GPUHardwareDetails()
    }

    /// Fetches instantaneous GPU performance statistics and VRAM metrics from IOAccelerator.
    /// Uses fast-path direct property lookups to minimize CPU footprint (< 0.05ms per call).
    public static func fetchGPUHardwareDetails() -> GPUHardwareDetails? {
        var iterator: io_iterator_t = 0
        let matchDict = IOServiceMatching("IOAccelerator")
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iterator)
        guard kr == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var result: GPUHardwareDetails?

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer {
                IOObjectRelease(service)
            }

            // Direct property lookup for PerformanceStatistics
            guard let perfCF = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0
            ) else {
                continue
            }

            guard let perf = perfCF.takeRetainedValue() as? [String: Any] else {
                continue
            }

            // Parse Model Name (can be CFString or CFData)
            var modelName = "Apple Silicon GPU"
            if let modelCF = IORegistryEntryCreateCFProperty(service, "model" as CFString, kCFAllocatorDefault, 0) {
                let modelVal = modelCF.takeRetainedValue()
                if let str = modelVal as? String {
                    modelName = str
                } else if let data = modelVal as? Data, let str = String(data: data, encoding: .utf8) {
                    modelName = str.trimmingCharacters(in: .controlCharacters)
                }
            }

            // Parse GPU Core Count
            var coreCount = 0
            if let coreCF = IORegistryEntryCreateCFProperty(service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0) {
                let coreVal = coreCF.takeRetainedValue()
                if let num = coreVal as? NSNumber {
                    coreCount = num.intValue
                }
            }

            // Resilient numeric extraction from PerformanceStatistics dictionary
            let deviceUtil = (perf["Device Utilization %"] as? NSNumber)?.doubleValue ?? 0.0
            let rendererUtil = (perf["Renderer Utilization %"] as? NSNumber)?.doubleValue ?? 0.0
            let tilerUtil = (perf["Tiler Utilization %"] as? NSNumber)?.doubleValue ?? 0.0
            let allocMem = (perf["Alloc system memory"] as? NSNumber)?.uint64Value ?? 0
            let inUseMem = (perf["In use system memory"] as? NSNumber)?.uint64Value ?? 0

            let hasUnified = modelName.contains("Apple") || allocMem > 0

            result = GPUHardwareDetails(
                modelName: modelName,
                coreCount: coreCount,
                deviceUtilization: min(100.0, max(0.0, deviceUtil)),
                rendererUtilization: min(100.0, max(0.0, rendererUtil)),
                tilerUtilization: min(100.0, max(0.0, tilerUtil)),
                allocatedVRAMBytes: allocMem,
                inUseVRAMBytes: inUseMem,
                hasUnifiedMemory: hasUnified
            )
            break
        }

        return result
    }

    // MARK: - Hardware Fans & Fanless Architecture

    /// Result of querying hardware cooling and fan tachometers.
    public struct FanHardwareTelemetry: Sendable {
        public let fans: [FanTelemetry]
        public let isFanless: Bool

        public init(fans: [FanTelemetry], isFanless: Bool) {
            self.fans = fans
            self.isFanless = isFanless
        }
    }

    /// Checks if the host Mac model is architecturally fanless.
    public static func isFanlessArchitecture() -> Bool {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return false }
        var modelChars = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &modelChars, &size, nil, 0) == 0 else { return false }
        let clean = modelChars.map { UInt8(bitPattern: $0) }.prefix(while: { $0 != 0 })
        let model = String(decoding: clean, as: UTF8.self)

        if model.contains("MacBookAir") { return true }
        if model.contains("Virtual") || model.contains("VM") || model.contains("QEMU") { return true }
        let knownFanlessModels: Set<String> = [
            "MacBook8,1", "MacBook9,1", "MacBook10,1",
            "Mac14,2", "Mac14,15", "Mac15,2", "Mac15,12", "Mac15,13", "Mac17,3"
        ]
        return knownFanlessModels.contains(model)
    }

    /// Queries fan tachometer RPM values from AppleSMC, or detects fanless operation.
    // MARK: - Persistent AppleSMC Connection (RAII)

    /// Maintains a persistent Mach user client connection to AppleSMC with RAII lifecycle deallocation.
    public final class AppleSMCConnection: @unchecked Sendable {
        public static let shared = AppleSMCConnection()

        public struct SMCVersion {
            public var major: UInt8 = 0
            public var minor: UInt8 = 0
            public var build: UInt8 = 0
            public var reserved: UInt8 = 0
            public var release: UInt16 = 0
            public init() {}
        }
        public struct SMCPLimitData {
            public var version: UInt16 = 0
            public var length: UInt16 = 0
            public var cpuPLimit: UInt32 = 0
            public var gpuPLimit: UInt32 = 0
            public var memPLimit: UInt32 = 0
            public init() {}
        }
        public struct SMCKeyInfoData {
            public var dataSize: UInt32 = 0
            public var dataType: UInt32 = 0
            public var dataAttributes: UInt8 = 0
            public init() {}
        }
        public struct SMCKeyData {
            public var key: UInt32 = 0
            public var vers = SMCVersion()
            public var pLimitData = SMCPLimitData()
            public var keyInfo = SMCKeyInfoData()
            public var result: UInt8 = 0
            public var status: UInt8 = 0
            public var data8: UInt8 = 0
            public var data32: UInt32 = 0
            public var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
                       (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
            public init() {}
        }

        private var connection: io_connect_t = 0
        private let lock = NSLock()
        private var isOpen: Bool = false

        public init() {
            openConnection()
        }

        deinit {
            closeConnection()
        }

        private func openConnection() {
            var iterator: io_iterator_t = 0
            let matchDict = IOServiceMatching("AppleSMC")
            let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iterator)
            guard kr == KERN_SUCCESS else { return }
            defer { IOObjectRelease(iterator) }

            let service = IOIteratorNext(iterator)
            guard service != 0 else { return }
            defer { IOObjectRelease(service) }

            var conn: io_connect_t = 0
            if IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS {
                self.connection = conn
                self.isOpen = true
            }
        }

        private func closeConnection() {
            if isOpen && connection != 0 {
                IOServiceClose(connection)
                connection = 0
                isOpen = false
            }
        }

        public var isConnected: Bool {
            lock.lock()
            defer { lock.unlock() }
            return isOpen && connection != 0
        }

        public func callSMC(input: inout SMCKeyData, output: inout SMCKeyData) -> kern_return_t {
            lock.lock()
            defer { lock.unlock() }

            if !isOpen || connection == 0 {
                openConnection()
            }
            guard isOpen && connection != 0 else {
                return KERN_FAILURE
            }

            let inputSize = MemoryLayout<SMCKeyData>.stride
            var outputSize = MemoryLayout<SMCKeyData>.stride
            let kr = IOConnectCallStructMethod(connection, 2, &input, inputSize, &output, &outputSize)
            if kr != KERN_SUCCESS {
                closeConnection()
                openConnection()
                if isOpen && connection != 0 {
                    return IOConnectCallStructMethod(connection, 2, &input, inputSize, &output, &outputSize)
                }
            }
            return kr
        }

        public func close() {
            lock.lock()
            defer { lock.unlock() }
            closeConnection()
        }
    }

    /// Queries fan tachometer RPM values from AppleSMC, or detects fanless operation.
    public static func fetchFanTelemetry() -> FanHardwareTelemetry {
        let fanless = isFanlessArchitecture()
        if fanless {
            return FanHardwareTelemetry(fans: [], isFanless: true)
        }

        let smc = AppleSMCConnection.shared

        func fourCC(_ str: String) -> UInt32 {
            var res: UInt32 = 0
            var count = 0
            for byte in str.utf8.prefix(4) {
                res = (res << 8) | UInt32(byte)
                count += 1
            }
            while count < 4 {
                res = (res << 8) | 0x20
                count += 1
            }
            return res
        }

        // Read fan count: "FNum"
        var input = AppleSMCConnection.SMCKeyData()
        var output = AppleSMCConnection.SMCKeyData()
        input.key = fourCC("FNum")
        input.data8 = 9 // SMC_CMD_READ_KEYINFO
        guard smc.callSMC(input: &input, output: &output) == KERN_SUCCESS,
              output.result == 0 else {
            return FanHardwareTelemetry(fans: [], isFanless: true)
        }

        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = 5 // SMC_CMD_READ_BYTES
        guard smc.callSMC(input: &input, output: &output) == KERN_SUCCESS,
              output.result == 0,
              output.keyInfo.dataSize >= 1 else {
            return FanHardwareTelemetry(fans: [], isFanless: true)
        }

        let fanCount = Int(output.bytes.0)
        guard fanCount > 0 && fanCount <= 16 else {
            return FanHardwareTelemetry(fans: [], isFanless: true)
        }

        var detectedFans: [FanTelemetry] = []

        func readFanRPM(keyStr: String) -> Int? {
            var inCmd = AppleSMCConnection.SMCKeyData()
            var outCmd = AppleSMCConnection.SMCKeyData()
            inCmd.key = fourCC(keyStr)
            inCmd.data8 = 9
            guard smc.callSMC(input: &inCmd, output: &outCmd) == KERN_SUCCESS,
                  outCmd.result == 0 else { return nil }
            inCmd.keyInfo.dataSize = outCmd.keyInfo.dataSize
            inCmd.data8 = 5
            guard smc.callSMC(input: &inCmd, output: &outCmd) == KERN_SUCCESS,
                  outCmd.result == 0,
                  outCmd.keyInfo.dataSize >= 2 else { return nil }
            // Decode fpe2 fixed-point format (14 bits integer, 2 bits fraction)
            let b0 = UInt16(outCmd.bytes.0)
            let b1 = UInt16(outCmd.bytes.1)
            let rpm = Int((b0 << 6) | (b1 >> 2))
            return max(0, rpm)
        }

        for i in 0..<fanCount {
            let current = readFanRPM(keyStr: "F\(i)Ac") ?? 0
            let minRpm = readFanRPM(keyStr: "F\(i)Mn") ?? 0
            let maxRpm = readFanRPM(keyStr: "F\(i)Mx") ?? 6000
            let name = fanCount == 2 ? (i == 0 ? "Left Fan" : "Right Fan") : "Fan \(i + 1)"
            detectedFans.append(FanTelemetry(id: i, name: name, currentRPM: current, minRPM: minRpm, maxRPM: maxRpm))
        }

        return FanHardwareTelemetry(fans: detectedFans, isFanless: false)
    }
}
