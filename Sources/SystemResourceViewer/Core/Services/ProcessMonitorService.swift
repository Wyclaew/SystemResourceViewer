import AppKit
import Darwin
import Foundation

/// Result bundle containing sorted hierarchical process trees and top consumers.
public struct ProcessTelemetryResult: Sendable {
    public let allProcesses: [ProcessItem]
    public let topCPU: [ProcessItem]
    public let topMemory: [ProcessItem]

    public init(
        allProcesses: [ProcessItem] = [],
        topCPU: [ProcessItem] = [],
        topMemory: [ProcessItem] = []
    ) {
        self.allProcesses = allProcesses
        self.topCPU = topCPU
        self.topMemory = topMemory
    }
}

/// Actor-isolated telemetry service monitoring process-level CPU/memory with Task Manager-style hierarchy.
public actor ProcessMonitorService {
    private struct ProcessTimeSample {
        let timestamp: UInt64
        let userTimeNs: UInt64
        let systemTimeNs: UInt64
    }

    private var previousSamples: [pid_t: ProcessTimeSample] = [:]
    private var iconCache: [pid_t: NSImage] = [:]
    private var nameCache: [pid_t: String] = [:]
    private var bundleIdCache: [pid_t: String] = [:]
    private var pathCache: [pid_t: String] = [:]
    private var architectureCache: [pid_t: String] = [:]
    private var categoryCache: [pid_t: ProcessCategory] = [:]
    private var usernameCache: [uid_t: String] = [:]
    private let defaultAppIcon: NSImage

    public init() {
        self.defaultAppIcon = NSWorkspace.shared.icon(for: .application)
    }

    /// Scans active processes, calculates deltas, and structures them into a Task Manager-style parent-child tree.
    public func pollProcesses(coreCount: Int, totalHardwareCPU: Double = 0.0, maxLimit: Int = 100) -> ProcessTelemetryResult {
        let entries = DarwinMachBridge.listAllProcessEntries()
        let nowNs = DispatchTime.now().uptimeNanoseconds

        struct RawItem {
            let pid: pid_t
            let ppid: pid_t
            let uid: uid_t
            let name: String
            let cpuPercentage: Double
            let residentBytes: UInt64
            let threadCount: Int
        }

        var rawItems: [pid_t: RawItem] = [:]
        rawItems.reserveCapacity(entries.count)

        var newSamples: [pid_t: ProcessTimeSample] = [:]
        newSamples.reserveCapacity(entries.count)

        for entry in entries {
            let pid = entry.pid
            guard pid > 0 else { continue }

            var cpuPercent = 0.0
            var residentBytes: UInt64 = 0
            var threadCount = 1

            if let taskInfo = DarwinMachBridge.fetchProcessTaskInfo(for: pid) {
                residentBytes = taskInfo.residentBytes
                threadCount = taskInfo.threadCount

                let currentSample = ProcessTimeSample(
                    timestamp: nowNs,
                    userTimeNs: taskInfo.userTimeNs,
                    systemTimeNs: taskInfo.systemTimeNs
                )
                newSamples[pid] = currentSample

                if let prev = previousSamples[pid] {
                    let timeDeltaNs = nowNs > prev.timestamp ? nowNs - prev.timestamp : 0
                    let totalWorkNs = (taskInfo.userTimeNs >= prev.userTimeNs ? taskInfo.userTimeNs - prev.userTimeNs : 0) +
                                      (taskInfo.systemTimeNs >= prev.systemTimeNs ? taskInfo.systemTimeNs - prev.systemTimeNs : 0)

                    if timeDeltaNs > 0 {
                        let rawPercent = (Double(totalWorkNs) / Double(timeDeltaNs)) * 100.0
                        let maxAllowed = Double(max(1, coreCount)) * 100.0
                        cpuPercent = min(maxAllowed, max(0.0, rawPercent))
                    }
                }
            }

            rawItems[pid] = RawItem(
                pid: pid,
                ppid: entry.ppid,
                uid: entry.uid,
                name: entry.name,
                cpuPercentage: cpuPercent,
                residentBytes: residentBytes,
                threadCount: threadCount
            )
        }

        self.previousSamples = newSamples

        // Clean up stale caches
        let currentPIDs = Set(entries.map(\.pid))
        if iconCache.count > currentPIDs.count + 50 {
            iconCache = iconCache.filter { currentPIDs.contains($0.key) }
            nameCache = nameCache.filter { currentPIDs.contains($0.key) }
            bundleIdCache = bundleIdCache.filter { currentPIDs.contains($0.key) }
            pathCache = pathCache.filter { currentPIDs.contains($0.key) }
            architectureCache = architectureCache.filter { currentPIDs.contains($0.key) }
            categoryCache = categoryCache.filter { currentPIDs.contains($0.key) }
        }

        // Convert to ProcessItem objects
        var itemMap: [pid_t: ProcessItem] = [:]
        itemMap.reserveCapacity(rawItems.count)

        for (pid, raw) in rawItems {
            let item = buildProcessItem(
                pid: pid,
                ppid: raw.ppid,
                uid: raw.uid,
                fallbackName: raw.name,
                cpu: raw.cpuPercentage,
                memory: raw.residentBytes,
                threadCount: raw.threadCount
            )
            itemMap[pid] = item
        }

        // Build Task Manager-style Parent-Child Hierarchy
        // Group children into parent's children array
        var childrenByParent: [pid_t: [ProcessItem]] = [:]
        for (_, item) in itemMap {
            if item.ppid > 1 && itemMap[item.ppid] != nil && item.ppid != item.id {
                childrenByParent[item.ppid, default: []].append(item)
            }
        }

        var rootItems: [ProcessItem] = []
        rootItems.reserveCapacity(itemMap.count)

        for (_, item) in itemMap {
            // An item is a root process if ppid <= 1, or its parent is not in itemMap
            let isChild = (item.ppid > 1 && itemMap[item.ppid] != nil && item.ppid != item.id)
            if !isChild {
                var root = item
                if let directChildren = childrenByParent[root.id] {
                    // Sort children by CPU descending
                    root.children = directChildren.sorted { $0.cpuPercentage > $1.cpuPercentage }
                }
                rootItems.append(root)
            }
        }

        // Sort Top 5 by aggregate total CPU
        let topCPU = Array(rootItems
            .sorted { $0.totalCPU > $1.totalCPU }
            .prefix(5))

        // Sort Top 5 by aggregate total Memory
        let topMemory = Array(rootItems
            .sorted { $0.totalMemory > $1.totalMemory }
            .prefix(5))

        // Return root items prioritized by total load
        let sortedRoots = rootItems
            .filter { $0.totalCPU > 0.05 || $0.totalMemory > (5 * 1024 * 1024) }
            .sorted { $0.totalCPU > $1.totalCPU }

        var finalProcesses = Array(sortedRoots.prefix(maxLimit))

        // Add synthetic "macOS System & Kernel" row for unaccounted CPU
        // This accounts for kernel threads, interrupt handlers, and permission-denied system daemons
        if totalHardwareCPU > 0.5 {
            let visibleCPUSum = finalProcesses.reduce(0.0) { $0 + $1.totalCPU }
            let kernelCPU = max(0.0, totalHardwareCPU - visibleCPUSum)
            if kernelCPU > 0.5 {
                let kernelItem = ProcessItem(
                    id: -1,
                    ppid: 0,
                    name: "macOS System & Kernel",
                    bundleIdentifier: nil,
                    cpuPercentage: kernelCPU,
                    memoryBytes: 0,
                    icon: nil,
                    children: [],
                    architecture: "Apple Silicon",
                    threadCount: 0,
                    ownerUser: "root",
                    executablePath: nil,
                    category: .system
                )
                finalProcesses.append(kernelItem)
            }
        }

        return ProcessTelemetryResult(
            allProcesses: finalProcesses,
            topCPU: topCPU,
            topMemory: topMemory
        )
    }

    private func buildProcessItem(
        pid: pid_t,
        ppid: pid_t,
        uid: uid_t,
        fallbackName: String,
        cpu: Double,
        memory: UInt64,
        threadCount: Int
    ) -> ProcessItem {
        let (name, bundleId, icon, path, arch, category) = resolveProcessMetadata(for: pid, uid: uid, fallbackName: fallbackName)
        let owner = resolveUsername(for: uid)

        return ProcessItem(
            id: pid,
            ppid: ppid,
            name: name,
            bundleIdentifier: bundleId,
            cpuPercentage: cpu,
            memoryBytes: memory,
            icon: icon,
            children: [],
            architecture: arch,
            threadCount: threadCount,
            ownerUser: owner,
            executablePath: path,
            category: category
        )
    }

    private func resolveUsername(for uid: uid_t) -> String {
        if let cached = usernameCache[uid] {
            return cached
        }
        let resolved: String
        if let pwd = getpwuid(uid) {
            resolved = String(cString: pwd.pointee.pw_name)
        } else {
            resolved = "\(uid)"
        }
        usernameCache[uid] = resolved
        return resolved
    }

    private func resolveProcessMetadata(
        for pid: pid_t,
        uid: uid_t,
        fallbackName: String
    ) -> (name: String, bundleId: String?, icon: NSImage, path: String?, arch: String, category: ProcessCategory) {
        if let cachedName = nameCache[pid],
           let cachedIcon = iconCache[pid],
           let cachedArch = architectureCache[pid],
           let cachedCategory = categoryCache[pid] {
            return (cachedName, bundleIdCache[pid], cachedIcon, pathCache[pid], cachedArch, cachedCategory)
        }

        var resolvedName: String?
        var resolvedBundleId: String?
        var resolvedIcon: NSImage?
        let path = pathCache[pid] ?? DarwinMachBridge.processExecutablePath(for: pid)
        if let path {
            pathCache[pid] = path
        }

        if let app = NSRunningApplication(processIdentifier: pid) {
            resolvedName = app.localizedName
            resolvedBundleId = app.bundleIdentifier
            resolvedIcon = app.icon
        }

        if let path {
            let lastComponent = (path as NSString).lastPathComponent
            if resolvedName == nil {
                if lastComponent.contains("qemu-system") {
                    resolvedName = "Android Emulator (QEMU)"
                } else if !lastComponent.isEmpty {
                    resolvedName = lastComponent
                }
            }

            if resolvedIcon == nil {
                resolvedIcon = NSWorkspace.shared.icon(forFile: path)
            }
        }

        let cleanFallback = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = resolvedName ?? (cleanFallback.isEmpty ? "Process \(pid)" : cleanFallback)
        let finalIcon = resolvedIcon ?? defaultAppIcon

        let isRosetta = DarwinMachBridge.isRosettaTranslated(pid: pid)
        let arch = isRosetta ? "Rosetta 2" : "Apple Silicon"

        // Category Classification Rules:
        let category: ProcessCategory
        if let path, !path.isEmpty {
            if path.contains("/Applications/") || path.hasPrefix("/System/Applications/") || resolvedBundleId != nil {
                category = .apps
            } else if path.contains("LaunchDaemons") || path.contains("LaunchAgents") {
                category = .daemons
            } else if path.hasPrefix("/usr/sbin") || path.hasPrefix("/usr/libexec") || path.hasPrefix("/System/Library/") || path.hasPrefix("/System/Cryptexes/") || uid == 0 {
                category = .system
            } else {
                category = (uid == 0) ? .system : .daemons
            }
        } else if resolvedBundleId != nil {
            category = .apps
        } else if uid == 0 {
            category = .system
        } else {
            category = .daemons
        }

        nameCache[pid] = finalName
        bundleIdCache[pid] = resolvedBundleId
        iconCache[pid] = finalIcon
        architectureCache[pid] = arch
        categoryCache[pid] = category

        return (finalName, resolvedBundleId, finalIcon, path, arch, category)
    }
}
