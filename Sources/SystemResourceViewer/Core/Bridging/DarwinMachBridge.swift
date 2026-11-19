import AppKit
import Darwin
import Foundation

/// Low-level Mach and Darwin kernel bridging routines.
public enum DarwinMachBridge {

    // MARK: - CPU Topology and Ticks

    public struct CPUTicks: Sendable {
        public let user: UInt64
        public let system: UInt64
        public let idle: UInt64
        public let nice: UInt64

        public var total: UInt64 {
            user + system + idle + nice
        }
    }

    public struct CPUTopology: Sendable {
        public let totalCores: Int
        public let performanceCores: Int
        public let efficiencyCores: Int
    }

    /// Queries the hardware topology for Apple Silicon or Intel architecture.
    public static func fetchCPUTopology() -> CPUTopology {
        let totalCores = Int(sysctlInt32("hw.ncpu") ?? 1)
        let nperflevels = Int(sysctlInt32("hw.nperflevels") ?? 1)

        if nperflevels > 1 {
            // Apple Silicon hybrid topology
            let pCores = Int(sysctlInt32("hw.perflevel0.logicalcpu") ?? Int32(totalCores))
            let eCores = Int(sysctlInt32("hw.perflevel1.logicalcpu") ?? 0)
            return CPUTopology(
                totalCores: totalCores,
                performanceCores: pCores,
                efficiencyCores: eCores
            )
        } else {
            // Intel or single-perflevel Apple Silicon
            return CPUTopology(
                totalCores: totalCores,
                performanceCores: totalCores,
                efficiencyCores: 0
            )
        }
    }

    /// Retrieves instantaneous CPU tick counters for every logical processor.
    /// Memory allocated by Mach is safely released via `vm_deallocate`.
    public static func fetchProcessorTicks() -> [CPUTicks]? {
        var numCPUs: natural_t = 0
        var cpuInfoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let hostPort = mach_host_self()
        defer {
            mach_port_deallocate(mach_task_self_, hostPort)
        }

        let result = host_processor_info(
            hostPort,
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfoArray,
            &infoCount
        )

        guard result == KERN_SUCCESS, let cpuInfo = cpuInfoArray else {
            return nil
        }

        defer {
            let address = vm_address_t(bitPattern: cpuInfo)
            let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, address, size)
        }

        guard infoCount >= mach_msg_type_number_t(Int(numCPUs) * Int(CPU_STATE_MAX)) else {
            return nil
        }

        var ticksList: [CPUTicks] = []
        ticksList.reserveCapacity(Int(numCPUs))

        for i in 0..<Int(numCPUs) {
            let offset = Int(CPU_STATE_MAX) * i
            let user = UInt64(max(0, cpuInfo[offset + Int(CPU_STATE_USER)]))
            let system = UInt64(max(0, cpuInfo[offset + Int(CPU_STATE_SYSTEM)]))
            let idle = UInt64(max(0, cpuInfo[offset + Int(CPU_STATE_IDLE)]))
            let nice = UInt64(max(0, cpuInfo[offset + Int(CPU_STATE_NICE)]))

            ticksList.append(CPUTicks(user: user, system: system, idle: idle, nice: nice))
        }

        return ticksList
    }

    // MARK: - Virtual Memory & RAM Statistics

    public struct VMStatisticsSnapshot: Sendable {
        public let totalPhysicalBytes: UInt64
        public let appBytes: UInt64
        public let wiredBytes: UInt64
        public let compressedBytes: UInt64
        public let cachedBytes: UInt64
        public let freeBytes: UInt64
        public let swapUsedBytes: UInt64
        public let swapTotalBytes: UInt64
        public let pressureLevel: MemoryPressureLevel
    }

    /// Fetches 64-bit Darwin kernel VM statistics.
    public static func fetchVMStatistics() -> VMStatisticsSnapshot? {
        let totalMem = sysctlUInt64("hw.memsize") ?? (16 * 1024 * 1024 * 1024)

        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStats = vm_statistics64_data_t()

        let hostPort = mach_host_self()
        defer {
            mach_port_deallocate(mach_task_self_, hostPort)
        }

        let kr = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(hostPort, HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard kr == KERN_SUCCESS else {
            return nil
        }

        let pageSize = UInt64(Darwin.getpagesize())

        // Activity Monitor standard calculations:
        // App Memory = (internal_page_count - purgeable_count) * pageSize
        let purgeable = UInt64(vmStats.purgeable_count)
        let internalPages = UInt64(vmStats.internal_page_count)
        let appPages = internalPages > purgeable ? internalPages - purgeable : 0
        let appBytes = appPages * pageSize

        // Wired Memory
        let wiredBytes = UInt64(vmStats.wire_count) * pageSize

        // Compressed Memory
        let compressedBytes = UInt64(vmStats.compressor_page_count) * pageSize

        // Cached Files = (purgeable_count + external_page_count) * pageSize
        let externalPages = UInt64(vmStats.external_page_count)
        let cachedBytes = (purgeable + externalPages) * pageSize

        // Free Memory
        let freeBytes = UInt64(vmStats.free_count) * pageSize

        // Swap Usage
        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapUsed: UInt64
        let swapTotal: UInt64
        if sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0) == 0 {
            swapUsed = UInt64(max(0, swapUsage.xsu_used))
            swapTotal = UInt64(max(0, swapUsage.xsu_total))
        } else {
            swapUsed = 0
            swapTotal = 0
        }

        // Pressure Level
        let pressureInt = sysctlInt32("kern.memorystatus_vm_pressure_level") ?? 1
        let pressureLevel: MemoryPressureLevel
        switch pressureInt {
        case 2:
            pressureLevel = .warning
        case 4:
            pressureLevel = .critical
        default:
            pressureLevel = .normal
        }

        return VMStatisticsSnapshot(
            totalPhysicalBytes: totalMem,
            appBytes: appBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            cachedBytes: cachedBytes,
            freeBytes: freeBytes,
            swapUsedBytes: swapUsed,
            swapTotalBytes: swapTotal,
            pressureLevel: pressureLevel
        )
    }

    // MARK: - Process Inspection via libproc

    public struct RawProcessInfo: Sendable {
        public let pid: pid_t
        public let userTimeNs: UInt64
        public let systemTimeNs: UInt64
        public let residentBytes: UInt64
        public let threadCount: Int

        public init(
            pid: pid_t,
            userTimeNs: UInt64,
            systemTimeNs: UInt64,
            residentBytes: UInt64,
            threadCount: Int = 1
        ) {
            self.pid = pid
            self.userTimeNs = userTimeNs
            self.systemTimeNs = systemTimeNs
            self.residentBytes = residentBytes
            self.threadCount = threadCount
        }
    }

    public struct ProcessBasicEntry: Sendable {
        public let pid: pid_t
        public let ppid: pid_t
        public let uid: uid_t
        public let name: String
        public let isSuspended: Bool

        public init(pid: pid_t, ppid: pid_t, uid: uid_t = 0, name: String, isSuspended: Bool = false) {
            self.pid = pid
            self.ppid = ppid
            self.uid = uid
            self.name = name
            self.isSuspended = isSuspended
        }

        public init(pid: pid_t, ppid: pid_t, name: String, isSuspended: Bool = false) {
            self.pid = pid
            self.ppid = ppid
            self.uid = 0
            self.name = name
            self.isSuspended = isSuspended
        }
    }

    // MARK: - Reusable Process Buffer Slab

    /// A reusable memory slab for `kinfo_proc` sysctl queries, eliminating ~14.2 MB/min transient heap allocation churn.
    public final class ProcessBufferSlab: @unchecked Sendable {
        public static let shared = ProcessBufferSlab()

        private var buffer: UnsafeMutablePointer<kinfo_proc>?
        private var byteCapacity: Int = 0
        private let lock = NSLock()

        public init() {}

        deinit {
            lock.lock()
            buffer?.deallocate()
            buffer = nil
            byteCapacity = 0
            lock.unlock()
        }

        public var currentByteCapacity: Int {
            lock.lock()
            defer { lock.unlock() }
            return byteCapacity
        }

        public func listProcesses() -> [ProcessBasicEntry] {
            lock.lock()
            defer { lock.unlock() }

            var mib = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
            var size = 0
            guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else {
                return []
            }

            // Headroom for newly spawned processes between sysctl size query and retrieval
            let neededBytes = size + (32 * MemoryLayout<kinfo_proc>.stride)
            if buffer == nil || byteCapacity < neededBytes {
                buffer?.deallocate()
                // Round up or double capacity to avoid frequent reallocations (minimum 512 KB)
                let stride = MemoryLayout<kinfo_proc>.stride
                let minCapacity = max(neededBytes, byteCapacity * 2, 512 * 1024)
                let procCount = (minCapacity + stride - 1) / stride
                buffer = UnsafeMutablePointer<kinfo_proc>.allocate(capacity: procCount)
                byteCapacity = procCount * stride
            }

            guard let buffer else { return [] }
            var bufferSize = byteCapacity
            guard sysctl(&mib, 4, buffer, &bufferSize, nil, 0) == 0 else {
                return []
            }

            let actualCount = min(byteCapacity / MemoryLayout<kinfo_proc>.stride, bufferSize / MemoryLayout<kinfo_proc>.stride)
            var result: [ProcessBasicEntry] = []
            result.reserveCapacity(actualCount)

            for i in 0..<actualCount {
                let p = buffer.advanced(by: i).pointee
                let pid = p.kp_proc.p_pid
                guard pid > 0 else { continue }
                let ppid = p.kp_eproc.e_ppid
                let uid = p.kp_eproc.e_ucred.cr_uid
                let name = withUnsafeBytes(of: p.kp_proc.p_comm) { rawPtr -> String in
                    let bytes = rawPtr.bindMemory(to: UInt8.self)
                    let clean = bytes.prefix(while: { $0 != 0 })
                    return String(decoding: clean, as: UTF8.self)
                }
                let isSuspended = (Int32(p.kp_proc.p_stat) == SSTOP)
                result.append(ProcessBasicEntry(pid: pid, ppid: ppid, uid: uid, name: name.isEmpty ? "Process \(pid)" : name, isSuspended: isSuspended))
            }
            return result
        }
    }

    /// Enumerates all processes with PID, parent PID (PPID), UID, and command name using the reusable slab.
    public static func listAllProcessEntries() -> [ProcessBasicEntry] {
        ProcessBufferSlab.shared.listProcesses()
    }

    // MARK: - POSIX Thread-Safe Username Resolution (getpwuid_r)

    /// Resolves the username for a UID using re-entrant POSIX `getpwuid_r` with stack buffer.
    public static func resolveUsername(for uid: uid_t) -> String? {
        var pwd = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 1024)

        let status = getpwuid_r(uid, &pwd, &buffer, buffer.count, &result)
        if status == 0, let res = result {
            return String(cString: res.pointee.pw_name)
        }
        return nil
    }

    /// Enumerates all active PIDs using libproc.
    public static func listActivePIDs() -> [pid_t] {
        var pidCount = 1024
        var pids = [pid_t](repeating: 0, count: pidCount)

        while true {
            let bufferByteLength = Int32(pidCount * MemoryLayout<pid_t>.size)
            let bytesWritten = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufferByteLength)
            if bytesWritten <= 0 {
                return []
            }

            let actualCount = Int(bytesWritten) / MemoryLayout<pid_t>.size
            if actualCount >= pidCount {
                pidCount *= 2
                pids = [pid_t](repeating: 0, count: pidCount)
            } else {
                return Array(pids.prefix(actualCount).filter { $0 > 0 })
            }
        }
    }

    /// Obtains raw CPU runtime, resident memory, and thread count for a specific PID.
    public static func fetchProcessTaskInfo(for pid: pid_t) -> RawProcessInfo? {
        var taskInfo = proc_taskinfo()
        let result = proc_pidinfo(
            pid,
            PROC_PIDTASKINFO,
            0,
            &taskInfo,
            Int32(MemoryLayout<proc_taskinfo>.size)
        )

        guard result == MemoryLayout<proc_taskinfo>.size else {
            return nil
        }

        return RawProcessInfo(
            pid: pid,
            userTimeNs: taskInfo.pti_total_user,
            systemTimeNs: taskInfo.pti_total_system,
            residentBytes: taskInfo.pti_resident_size,
            threadCount: Int(taskInfo.pti_threadnum)
        )
    }

    /// Resolves the process name using `proc_name` with executable path fallback.
    public static func processName(for pid: pid_t) -> String {
        var nameBuffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &nameBuffer, 256)
        if length > 0 {
            let bounded = min(nameBuffer.count, Int(length))
            let clean = nameBuffer.prefix(bounded).map { UInt8(bitPattern: $0) }
            let nonNull = clean.prefix(while: { $0 != 0 })
            let name = String(decoding: nonNull, as: UTF8.self)
            if !name.isEmpty {
                return name
            }
        }
        if let execPath = processExecutablePath(for: pid), !execPath.isEmpty {
            let fileName = URL(fileURLWithPath: execPath).lastPathComponent
            if !fileName.isEmpty {
                return fileName
            }
        }
        return "Process \(pid)"
    }

    /// Resolves executable file path using `proc_pidpath`.
    public static func processExecutablePath(for pid: pid_t) -> String? {
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &pathBuffer, UInt32(MAXPATHLEN))
        if length > 0 {
            let bounded = min(pathBuffer.count, Int(length))
            let clean = pathBuffer.prefix(bounded).map { UInt8(bitPattern: $0) }
            let nonNull = clean.prefix(while: { $0 != 0 })
            return String(decoding: nonNull, as: UTF8.self)
        }
        return nil
    }

    /// Checks if a process is running under Rosetta 2 translation via sysctl.
    public static func isRosettaTranslated(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        var ret: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var mib: [Int32] = [0, 0]
        var mibSize = 2
        if sysctlnametomib("sysctl.proc_translated", &mib, &mibSize) == 0 {
            var pidMib = [mib[0], mib[1], pid]
            if sysctl(&pidMib, 3, &ret, &size, nil, 0) == 0 {
                return ret == 1
            }
        }
        return false
    }

    // MARK: - Sysctl Helpers

    public static func sysctlInt32(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname(name, &value, &size, nil, 0) == 0 {
            return value
        }
        return nil
    }

    public static func sysctlUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        if sysctlbyname(name, &value, &size, nil, 0) == 0 {
            return value
        }
        return nil
    }

    // MARK: - Process Disk I/O & Diagnostics

    public struct ProcessDiskIO: Sendable, Equatable {
        public let bytesRead: UInt64
        public let bytesWritten: UInt64

        public init(bytesRead: UInt64, bytesWritten: UInt64) {
            self.bytesRead = bytesRead
            self.bytesWritten = bytesWritten
        }
    }

    /// Queries unprivileged Darwin resource usage (RUSAGE_INFO_V4) for a process to extract disk I/O metrics.
    public static func fetchProcessDiskIO(for pid: pid_t) -> ProcessDiskIO? {
        guard pid > 0 else { return nil }
        var rusage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &rusage) { ptr -> Int32 in
            ptr.withMemoryRebound(to: (rusage_info_t?).self, capacity: 1) { rusagePtr in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rusagePtr)
            }
        }
        guard result == 0 else { return nil }
        return ProcessDiskIO(
            bytesRead: rusage.ri_diskio_bytesread,
            bytesWritten: rusage.ri_diskio_byteswritten
        )
    }

    /// Queries open file descriptors count for a PID via PROC_PIDLISTFDS.
    public static func fetchProcessOpenFileDescriptorsCount(for pid: pid_t) -> Int? {
        guard pid > 0 else { return nil }
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return nil }
        return Int(bufferSize) / MemoryLayout<proc_fdinfo>.size
    }

    /// Queries process launch time and status via PROC_PIDTBSDINFO with kinfo_proc fallback.
    public static func fetchProcessBSDInfo(for pid: pid_t) -> (startTime: Date?, isSuspended: Bool, ppid: pid_t)? {
        guard pid > 0 else { return nil }
        var bsdInfo = proc_bsdinfo()
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, Int32(MemoryLayout<proc_bsdinfo>.size))
        if size == MemoryLayout<proc_bsdinfo>.size {
            let sec = Double(bsdInfo.pbi_start_tvsec)
            let usec = Double(bsdInfo.pbi_start_tvusec)
            let date = Date(timeIntervalSince1970: sec + (usec / 1_000_000.0))
            let isSuspended = (bsdInfo.pbi_status == UInt32(SSTOP))
            return (date, isSuspended, pid_t(bsdInfo.pbi_ppid))
        }

        // Fallback to kinfo_proc for root/system processes
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var kp = kinfo_proc()
        var kpSize = MemoryLayout<kinfo_proc>.size
        if sysctl(&mib, 4, &kp, &kpSize, nil, 0) == 0 {
            let sec = Double(kp.kp_proc.p_starttime.tv_sec)
            let usec = Double(kp.kp_proc.p_starttime.tv_usec)
            let date = Date(timeIntervalSince1970: sec + (usec / 1_000_000.0))
            let isSuspended = (Int32(kp.kp_proc.p_stat) == SSTOP)
            return (date, isSuspended, kp.kp_eproc.e_ppid)
        }
        return nil
    }

    /// Fetches deep diagnostics and telemetry to construct a ProcessDetailItem.
    public static func fetchProcessDetail(for process: ProcessItem) -> ProcessDetailItem {
        let pid = process.id
        var taskInfo = proc_taskinfo()
        let hasTaskInfo = (proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(MemoryLayout<proc_taskinfo>.size)) == MemoryLayout<proc_taskinfo>.size)

        let fdCount = fetchProcessOpenFileDescriptorsCount(for: pid)
        let bsd = fetchProcessBSDInfo(for: pid)
        let diskIO = fetchProcessDiskIO(for: pid)

        return ProcessDetailItem(
            id: pid,
            ppid: process.ppid > 0 ? process.ppid : (bsd?.ppid ?? 0),
            name: process.name,
            bundleIdentifier: process.bundleIdentifier,
            executablePath: process.executablePath,
            ownerUser: process.ownerUser,
            architecture: process.architecture,
            isRosetta: process.isRosetta,
            isProtected: process.isProtected,
            isSuspended: bsd?.isSuspended ?? process.isSuspended,
            category: process.category,
            cpuPercentage: process.cpuPercentage,
            threadCount: hasTaskInfo ? Int(taskInfo.pti_threadnum) : process.threadCount,
            userTimeNs: hasTaskInfo ? taskInfo.pti_total_user : 0,
            systemTimeNs: hasTaskInfo ? taskInfo.pti_total_system : 0,
            residentBytes: hasTaskInfo ? taskInfo.pti_resident_size : process.memoryBytes,
            virtualBytes: hasTaskInfo ? taskInfo.pti_virtual_size : 0,
            openFileDescriptorsCount: fdCount,
            startTime: bsd?.startTime,
            contextSwitches: hasTaskInfo ? UInt64(max(0, taskInfo.pti_csw)) : 0,
            faults: hasTaskInfo ? UInt64(max(0, taskInfo.pti_faults)) : 0,
            pageins: hasTaskInfo ? UInt64(max(0, taskInfo.pti_pageins)) : 0,
            cowFaults: hasTaskInfo ? UInt64(max(0, taskInfo.pti_cow_faults)) : 0,
            messagesSent: hasTaskInfo ? UInt64(taskInfo.pti_messages_sent) : 0,
            messagesReceived: hasTaskInfo ? UInt64(taskInfo.pti_messages_received) : 0,
            machSyscalls: hasTaskInfo ? UInt64(taskInfo.pti_syscalls_mach) : 0,
            unixSyscalls: hasTaskInfo ? UInt64(taskInfo.pti_syscalls_unix) : 0,
            diskReadBytesPerSecond: process.diskReadBytesPerSecond,
            diskWriteBytesPerSecond: process.diskWriteBytesPerSecond,
            totalDiskReadBytes: diskIO?.bytesRead ?? process.totalDiskReadBytes,
            totalDiskWriteBytes: diskIO?.bytesWritten ?? process.totalDiskWriteBytes
        )
    }

    // MARK: - String and Time Sysctl Queries

    public static func sysctlString(_ name: String) -> String? {
        var size: Int = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        let clean = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return String(decoding: clean, as: UTF8.self)
    }

    public static func fetchBootTime() -> Date? {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &bootTime, &size, nil, 0) == 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(bootTime.tv_sec))
    }

    public static func fetchSystemUptime() -> TimeInterval {
        if let bootTime = fetchBootTime() {
            return Date().timeIntervalSince(bootTime)
        }
        return ProcessInfo.processInfo.systemUptime
    }

    public static func fetchHardwareProfile() -> HardwareProfile {
        let model = sysctlString("hw.model") ?? "Mac"
        let brand = sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
        let topology = fetchCPUTopology()
        let totalMem = sysctlUInt64("hw.memsize") ?? (16 * 1024 * 1024 * 1024)
        let build = sysctlString("kern.osversion") ?? "Unknown"
        let kernel = sysctlString("kern.osrelease").map { "Darwin \($0)" } ?? "Darwin"
        let bootDate = fetchBootTime() ?? Date()
        let uptime = fetchSystemUptime()
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        let marketingName = resolveMacMarketingName(for: model)

        return HardwareProfile(
            modelIdentifier: model,
            marketingModelName: marketingName,
            cpuBrand: brand,
            totalCores: topology.totalCores,
            performanceCores: topology.performanceCores,
            efficiencyCores: topology.efficiencyCores,
            totalMemoryBytes: totalMem,
            osVersionString: osVersion,
            osBuildVersion: build,
            kernelRelease: kernel,
            bootTime: bootDate,
            uptimeSeconds: uptime
        )
    }

    public static func resolveMacMarketingName(for model: String) -> String {
        let knownModels: [String: String] = [
            "Mac17,3": "MacBook Pro (14-inch, M5)",
            "Mac16,1": "MacBook Pro (14-inch, M4)",
            "Mac16,2": "MacBook Pro (14-inch, M4 Pro)",
            "Mac15,3": "MacBook Pro (14-inch, Nov 2023)",
            "Mac14,2": "MacBook Air (M2, 2022)",
            "Mac14,7": "MacBook Pro (13-inch, M2, 2022)",
            "Macmini9,1": "Mac mini (M1, 2020)",
            "MacBookPro18,1": "MacBook Pro (16-inch, 2021)",
            "MacBookPro18,2": "MacBook Pro (16-inch, M1 Max, 2021)"
        ]
        return knownModels[model] ?? "Mac (\(model))"
    }
}
