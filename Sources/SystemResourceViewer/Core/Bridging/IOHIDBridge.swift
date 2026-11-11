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

        private var dylibHandle: UnsafeMutableRawPointer?
        private var client: CFTypeRef?
        private var fnClientCopyServices: ClientCopyServicesFn?
        private var fnServiceCopyProperty: ServiceCopyPropertyFn?
        private var fnServiceCopyEvent: ServiceCopyEventFn?
        private var fnEventGetFloatValue: EventGetFloatValueFn?

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
        }

        deinit {
            client = nil
            if let handle = dylibHandle {
                dlclose(handle)
            }
        }

        /// Queries the active temperature sensors and synthesizes die average, peak, battery, and storage temperatures.
        public func sample() -> ThermalSensorSnapshot? {
            guard let client = client,
                  let fnCopyServices = fnClientCopyServices,
                  let fnCopyProperty = fnServiceCopyProperty,
                  let fnCopyEvent = fnServiceCopyEvent,
                  let fnGetFloat = fnEventGetFloatValue else {
                return nil
            }

            guard let servicesUnmanaged = fnCopyServices(client) else {
                return nil
            }
            let services = servicesUnmanaged.takeRetainedValue() as [AnyObject]

            var dieSensors: [String: Double] = [:]
            var batteryTemps: [Double] = []
            var storageTemps: [Double] = []

            // IOHIDEventTypeTemperature = 15 (0xF)
            let eventTypeTemp: Int64 = 15
            let field = UInt32(15 << 16)

            for item in services {
                let service = item as CFTypeRef
                guard let propUnmanaged = fnCopyProperty(service, "Product" as CFString) else {
                    continue
                }
                let product = propUnmanaged.takeRetainedValue() as? String ?? ""

                guard let eventUnmanaged = fnCopyEvent(service, eventTypeTemp, 0, 0) else {
                    continue
                }
                let event = eventUnmanaged.takeRetainedValue()
                let value = fnGetFloat(event, field)

                // Reject uncalibrated or inactive readings
                guard value >= 10.0 && value <= 125.0 else { continue }

                if product.contains("tdie") && !product.contains("tcal") {
                    dieSensors[product] = value
                } else if product.contains("battery") || product.contains("gas gauge") {
                    batteryTemps.append(value)
                } else if product.contains("NAND") || product.contains("storage") {
                    storageTemps.append(value)
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
