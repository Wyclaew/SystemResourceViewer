import Foundation
import IOKit

/// Low-level bridging to macOS IOHIDEventSystemClient for real-time hardware temperature sensors.
public enum IOHIDBridge {

    /// Snapshot of temperature channels captured from the IOHID event subsystem.
    public struct ThermalSensorSnapshot: Sendable, Equatable {
        public let socDieAverageTemperature: Double?
        public let socDiePeakTemperature: Double?
        public let batteryTemperature: Double?
        public let storageTemperature: Double?
        public let individualDieSensors: [String: Double]

        public init(
            socDieAverageTemperature: Double?,
            socDiePeakTemperature: Double?,
            batteryTemperature: Double?,
            storageTemperature: Double?,
            individualDieSensors: [String: Double]
        ) {
            self.socDieAverageTemperature = socDieAverageTemperature
            self.socDiePeakTemperature = socDiePeakTemperature
            self.batteryTemperature = batteryTemperature
            self.storageTemperature = storageTemperature
            self.individualDieSensors = individualDieSensors
        }
    }

    /// Internal wrapper managing a persistent IOHIDEventSystemClientRef to avoid per-sample initialization overhead.
    public final class ClientWrapper: @unchecked Sendable {
        private typealias ClientCreateFn = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
        private typealias ClientSetMatchingFn = @convention(c) (CFTypeRef, CFDictionary) -> Void
        private typealias ClientCopyServicesFn = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
        private typealias ServiceCopyPropertyFn = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
        private typealias ServiceCopyEventFn = @convention(c) (CFTypeRef, Int64, Int32, Int64) -> Unmanaged<CFTypeRef>?
        private typealias EventGetFloatValueFn = @convention(c) (CFTypeRef, UInt32) -> Double

        /// Classified sensor metadata cached upon initial discovery to eliminate per-tick string query overhead.
        public struct SensorMetadata: @unchecked Sendable {
            public enum Kind: Sendable, Equatable {
                case die(product: String)
                case battery
                case storage
                case other
            }
            public let service: CFTypeRef
            public let product: String
            public let kind: Kind
        }

        private var dylibHandle: UnsafeMutableRawPointer?
        private var client: CFTypeRef?
        private var fnClientCopyServices: ClientCopyServicesFn?
        private var fnServiceCopyProperty: ServiceCopyPropertyFn?
        private var fnServiceCopyEvent: ServiceCopyEventFn?
        private var fnEventGetFloatValue: EventGetFloatValueFn?
        private var cachedSensors: [SensorMetadata]?

        public init?() {
            guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else {
                return nil
            }
            self.dylibHandle = handle

            guard let pCreate = dlsym(handle, "IOHIDEventSystemClientCreate"),
                  let pSetMatching = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
                  let pCopyServices = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
                  let pCopyProperty = dlsym(handle, "IOHIDServiceClientCopyProperty"),
                  let pCopyEvent = dlsym(handle, "IOHIDServiceClientCopyEvent"),
                  let pGetFloat = dlsym(handle, "IOHIDEventGetFloatValue") else {
                dlclose(handle)
                return nil
            }

            let fnCreate = unsafeBitCast(pCreate, to: ClientCreateFn.self)
            let fnSetMatching = unsafeBitCast(pSetMatching, to: ClientSetMatchingFn.self)
            self.fnClientCopyServices = unsafeBitCast(pCopyServices, to: ClientCopyServicesFn.self)
            self.fnServiceCopyProperty = unsafeBitCast(pCopyProperty, to: ServiceCopyPropertyFn.self)
            self.fnServiceCopyEvent = unsafeBitCast(pCopyEvent, to: ServiceCopyEventFn.self)
            self.fnEventGetFloatValue = unsafeBitCast(pGetFloat, to: EventGetFloatValueFn.self)

            guard let clientUnmanaged = fnCreate(kCFAllocatorDefault) else {
                dlclose(handle)
                return nil
            }
            let clientRef = clientUnmanaged.takeRetainedValue()
            self.client = clientRef

            // Match PrimaryUsagePage: 0xFF00 (Apple Vendor), PrimaryUsage: 5 (Temperature Sensor)
            let matchDict: [String: Any] = [
                "PrimaryUsagePage": 0xFF00,
                "PrimaryUsage": 5
            ]
            fnSetMatching(clientRef, matchDict as CFDictionary)

            // Pre-classify and cache sensor metadata on discovery
            _ = discoverAndCacheSensors()
        }

        deinit {
            cachedSensors = nil
            client = nil
            if let handle = dylibHandle {
                dlclose(handle)
            }
        }

        /// Discovers, queries Product strings once, and caches matching temperature sensors.
        @discardableResult
        public func discoverAndCacheSensors() -> [SensorMetadata] {
            guard let client = client,
                  let fnCopyServices = fnClientCopyServices,
                  let fnCopyProperty = fnServiceCopyProperty else {
                return []
            }
            guard let servicesUnmanaged = fnCopyServices(client) else {
                return []
            }
            let services = servicesUnmanaged.takeRetainedValue() as [AnyObject]
            var result: [SensorMetadata] = []
            result.reserveCapacity(services.count)

            for item in services {
                let service = item as CFTypeRef
                guard let propUnmanaged = fnCopyProperty(service, "Product" as CFString) else {
                    continue
                }
                let product = propUnmanaged.takeRetainedValue() as? String ?? ""

                let kind: SensorMetadata.Kind
                if product.contains("tdie") && !product.contains("tcal") {
                    kind = .die(product: product)
                } else if product.contains("battery") || product.contains("gas gauge") {
                    kind = .battery
                } else if product.contains("NAND") || product.contains("storage") {
                    kind = .storage
                } else {
                    kind = .other
                }

                if kind != .other {
                    result.append(SensorMetadata(service: service, product: product, kind: kind))
                }
            }

            self.cachedSensors = result
            return result
        }

        public var cachedSensorCount: Int {
            cachedSensors?.count ?? 0
        }

        public func refreshSensorCache() {
            _ = discoverAndCacheSensors()
        }

        /// Queries active temperature sensors using cached metadata, reading raw float values without repeating string property lookups.
        public func sample() -> ThermalSensorSnapshot? {
            guard let fnCopyEvent = fnServiceCopyEvent,
                  let fnGetFloat = fnEventGetFloatValue else {
                return nil
            }

            let sensors = cachedSensors ?? discoverAndCacheSensors()
            guard !sensors.isEmpty else {
                return ThermalSensorSnapshot(
                    socDieAverageTemperature: nil,
                    socDiePeakTemperature: nil,
                    batteryTemperature: nil,
                    storageTemperature: nil,
                    individualDieSensors: [:]
                )
            }

            var dieSensors: [String: Double] = [:]
            var batteryTemps: [Double] = []
            var storageTemps: [Double] = []

            // IOHIDEventTypeTemperature = 15 (0xF)
            let eventTypeTemp: Int64 = 15
            let field = UInt32(15 << 16)

            for sensor in sensors {
                guard let eventUnmanaged = fnCopyEvent(sensor.service, eventTypeTemp, 0, 0) else {
                    continue
                }
                let event = eventUnmanaged.takeRetainedValue()
                let value = fnGetFloat(event, field)

                // Reject uncalibrated or inactive readings
                guard value >= 10.0 && value <= 125.0 else { continue }

                switch sensor.kind {
                case .die(let product):
                    dieSensors[product] = value
                case .battery:
                    batteryTemps.append(value)
                case .storage:
                    storageTemps.append(value)
                case .other:
                    break
                }
            }

            let avgDie: Double? = dieSensors.isEmpty ? nil :
                (dieSensors.values.reduce(0.0, +) / Double(dieSensors.count))
            let peakDie: Double? = dieSensors.values.max()
            let avgBat: Double? = batteryTemps.isEmpty ? nil :
                (batteryTemps.reduce(0.0, +) / Double(batteryTemps.count))
            let avgStor: Double? = storageTemps.isEmpty ? nil :
                (storageTemps.reduce(0.0, +) / Double(storageTemps.count))

            return ThermalSensorSnapshot(
                socDieAverageTemperature: avgDie,
                socDiePeakTemperature: peakDie,
                batteryTemperature: avgBat,
                storageTemperature: avgStor,
                individualDieSensors: dieSensors
            )
        }
    }
}
