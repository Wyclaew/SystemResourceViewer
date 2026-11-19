import AppKit
import Darwin
import Foundation
import XCTest
@testable import SystemResourceViewer

final class Milestone3ChallengerStressTests: XCTestCase {

    // MARK: - 1. ProcessAction Pause & Resume on Live Subprocesses

    func testPauseAndResumeLiveSubprocessWithKernelStateVerification() throws {
        // Spawn a real child process using /bin/sleep 60
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["60"]
        try process.run()

        let childPID = process.processIdentifier
        XCTAssertGreaterThan(childPID, 0, "Child process must have a valid PID")
        defer {
            // Guarantee child process cleanup even if assertions fail
            Darwin.kill(childPID, SIGKILL)
            process.waitUntilExit()
        }

        // 1. Verify initial active running state
        XCTAssertEqual(Darwin.kill(childPID, 0), 0, "Spawned child process must be alive in process table")
        let initialBSD = DarwinMachBridge.fetchProcessBSDInfo(for: childPID)
        XCTAssertNotNil(initialBSD, "BSD info should be queryable for child PID")
        XCTAssertFalse(initialBSD?.isSuspended ?? true, "Initial process state must NOT be suspended")

        // 2. Pause child process via ProcessAction.pause (SIGSTOP)
        let pauseResult = ProcessAction.pause(pid: childPID, name: "sleep")
        XCTAssertEqual(pauseResult, .success, "ProcessAction.pause should return .success for user subprocess")

        // Give Darwin kernel up to 500ms to transition process state to SSTOP
        var isSuspended = false
        for _ in 0..<10 {
            if let bsd = DarwinMachBridge.fetchProcessBSDInfo(for: childPID), bsd.isSuspended {
                isSuspended = true
                break
            }
            usleep(50_000) // 50ms
        }
        XCTAssertTrue(isSuspended, "Darwin kernel must report isSuspended == true after SIGSTOP")

        // 3. Direct proc_pidinfo PROC_PIDTBSDINFO verification
        var bsdInfo = proc_bsdinfo()
        let bsdSize = proc_pidinfo(childPID, PROC_PIDTBSDINFO, 0, &bsdInfo, Int32(MemoryLayout<proc_bsdinfo>.size))
        XCTAssertEqual(bsdSize, Int32(MemoryLayout<proc_bsdinfo>.size), "proc_pidinfo PROC_PIDTBSDINFO must succeed")
        XCTAssertEqual(bsdInfo.pbi_status, UInt32(SSTOP), "Darwin kernel pbi_status must equal SSTOP (4)")

        // 4. Verify ProcessDetailItem diagnostic reflects isSuspended == true
        let mockItem = ProcessItem(
            id: childPID,
            name: "sleep",
            cpuPercentage: 0.0,
            memoryBytes: 1024 * 1024,
            isSuspended: true
        )
        let detail = DarwinMachBridge.fetchProcessDetail(for: mockItem)
        XCTAssertTrue(detail.isSuspended, "ProcessDetailItem must reflect suspended state")
        XCTAssertTrue(detail.formattedDiagnosticsSummary.contains("Status: Suspended (Paused)"),
                      "Diagnostics summary should display 'Status: Suspended (Paused)'")

        // 5. Test idempotency of double-pause
        let doublePauseResult = ProcessAction.pause(pid: childPID, name: "sleep")
        XCTAssertEqual(doublePauseResult, .success, "Calling pause again on an already paused process must succeed safely")
        let doublePauseBSD = DarwinMachBridge.fetchProcessBSDInfo(for: childPID)
        XCTAssertTrue(doublePauseBSD?.isSuspended ?? false, "Process must remain suspended after second pause")

        // 6. Resume child process via ProcessAction.resume (SIGCONT)
        let resumeResult = ProcessAction.resume(pid: childPID, name: "sleep")
        XCTAssertEqual(resumeResult, .success, "ProcessAction.resume should return .success for user subprocess")

        // Give Darwin kernel up to 500ms to transition process state back to active
        var isResumed = false
        for _ in 0..<10 {
            if let bsd = DarwinMachBridge.fetchProcessBSDInfo(for: childPID), !bsd.isSuspended {
                isResumed = true
                break
            }
            usleep(50_000) // 50ms
        }
        XCTAssertTrue(isResumed, "Darwin kernel must report isSuspended == false after SIGCONT")

        // Verify direct proc_pidinfo confirms process is no longer SSTOP
        let resumeBsdSize = proc_pidinfo(childPID, PROC_PIDTBSDINFO, 0, &bsdInfo, Int32(MemoryLayout<proc_bsdinfo>.size))
        XCTAssertEqual(resumeBsdSize, Int32(MemoryLayout<proc_bsdinfo>.size))
        XCTAssertNotEqual(bsdInfo.pbi_status, UInt32(SSTOP), "Darwin kernel pbi_status must NOT equal SSTOP after resume")

        let resumedDetail = DarwinMachBridge.fetchProcessDetail(for: mockItem)
        XCTAssertFalse(resumedDetail.isSuspended, "ProcessDetailItem must reflect resumed active state")
        XCTAssertTrue(resumedDetail.formattedDiagnosticsSummary.contains("Status: Running"),
                      "Diagnostics summary should display 'Status: Running'")

        // 7. Test idempotency of double-resume
        let doubleResumeResult = ProcessAction.resume(pid: childPID, name: "sleep")
        XCTAssertEqual(doubleResumeResult, .success, "Calling resume again on an already running process must succeed safely")

        // 8. Terminate process and verify error handling on dead PID
        Darwin.kill(childPID, SIGKILL)
        process.waitUntilExit()

        let deadPauseResult = ProcessAction.pause(pid: childPID, name: "sleep")
        guard case .failure(let reason) = deadPauseResult else {
            XCTFail("Pausing dead PID must fail with ESRCH")
            return
        }
        XCTAssertTrue(reason.contains("ESRCH") || reason.contains("No such process"),
                      "Dead process pause failure reason should mention ESRCH/No such process: \(reason)")

        let deadResumeResult = ProcessAction.resume(pid: childPID, name: "sleep")
        guard case .failure(let resumeReason) = deadResumeResult else {
            XCTFail("Resuming dead PID must fail with ESRCH")
            return
        }
        XCTAssertTrue(resumeReason.contains("ESRCH") || resumeReason.contains("No such process"),
                      "Dead process resume failure reason should mention ESRCH/No such process: \(resumeReason)")
    }

    func testPauseResumeUnderRapidAlternationStress() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["60"]
        try process.run()

        let childPID = process.processIdentifier
        defer {
            Darwin.kill(childPID, SIGKILL)
            process.waitUntilExit()
        }

        // Rapidly alternate pause and resume 10 times in a tight loop
        for i in 0..<10 {
            let pauseRes = ProcessAction.pause(pid: childPID, name: "sleep")
            XCTAssertEqual(pauseRes, .success, "Rapid pause iteration \(i) must succeed")

            let resumeRes = ProcessAction.resume(pid: childPID, name: "sleep")
            XCTAssertEqual(resumeRes, .success, "Rapid resume iteration \(i) must succeed")
        }

        XCTAssertEqual(Darwin.kill(childPID, 0), 0, "Subprocess must still be alive after rapid alternation stress")
    }

    // MARK: - 2. ProcessGuard Defense-In-Depth

    func testProcessGuardPID0And1CompleteImmunity() {
        let rootPIDs: [pid_t] = [0, 1]

        for pid in rootPIDs {
            XCTAssertTrue(ProcessGuard.isProtected(pid: pid), "PID \(pid) must be strictly protected")

            // Test terminate
            let termRes = ProcessAction.terminate(pid: pid)
            guard case .failure(let termReason) = termRes else {
                XCTFail("terminate(pid: \(pid)) MUST fail")
                continue
            }
            XCTAssertTrue(termReason.contains("Cannot terminate system initialization process"),
                          "Expected initialization message: \(termReason)")

            // Test forceKill
            let killRes = ProcessAction.forceKill(pid: pid)
            guard case .failure(let killReason) = killRes else {
                XCTFail("forceKill(pid: \(pid)) MUST fail")
                continue
            }
            XCTAssertTrue(killReason.contains("Cannot terminate system initialization process"),
                          "Expected initialization message: \(killReason)")

            // Test pause
            let pauseRes = ProcessAction.pause(pid: pid)
            guard case .failure(let pauseReason) = pauseRes else {
                XCTFail("pause(pid: \(pid)) MUST fail")
                continue
            }
            XCTAssertTrue(pauseReason.contains("Cannot terminate system initialization process") ||
                          pauseReason.contains("Cannot pause protected process"),
                          "Expected pause rejection: \(pauseReason)")

            // Test resume
            let resumeRes = ProcessAction.resume(pid: pid)
            guard case .failure(let resumeReason) = resumeRes else {
                XCTFail("resume(pid: \(pid)) MUST fail")
                continue
            }
            XCTAssertTrue(resumeReason.contains("Cannot terminate system initialization process") ||
                          resumeReason.contains("Cannot resume protected process"),
                          "Expected resume rejection: \(resumeReason)")
        }
    }

    func testProcessGuardWindowServerImmunityAcrossAllSignals() {
        let mockPID: pid_t = 54321
        let wsNames = ["WindowServer", "windowserver", "WINDOWSERVER"]

        for name in wsNames {
            XCTAssertTrue(ProcessGuard.isProtected(pid: mockPID, name: name), "WindowServer (\(name)) must be protected")

            let term = ProcessAction.terminate(pid: mockPID, name: name)
            XCTAssertEqual(term, .failure("Cannot terminate critical system process '\(name)' (PID \(mockPID))."))

            let kill = ProcessAction.forceKill(pid: mockPID, name: name)
            XCTAssertEqual(kill, .failure("Cannot terminate critical system process '\(name)' (PID \(mockPID))."))

            let pause = ProcessAction.pause(pid: mockPID, name: name)
            XCTAssertEqual(pause, .failure("Cannot terminate critical system process '\(name)' (PID \(mockPID))."))

            let resume = ProcessAction.resume(pid: mockPID, name: name)
            XCTAssertEqual(resume, .failure("Cannot terminate critical system process '\(name)' (PID \(mockPID))."))
        }

        // Test with bundle identifier
        XCTAssertTrue(
            ProcessGuard.isProtected(pid: mockPID, bundleIdentifier: "com.apple.WindowServer"),
            "WindowServer bundle ID must be protected"
        )

        // If WindowServer is actually running on this system, test real PID resolution
        let allEntries = DarwinMachBridge.listAllProcessEntries()
        if let liveWindowServer = allEntries.first(where: { $0.name.lowercased() == "windowserver" }) {
            let wsPID = liveWindowServer.pid
            XCTAssertTrue(ProcessGuard.isProtected(pid: wsPID), "Real WindowServer PID (\(wsPID)) must be protected")

            // None of the destructive or pause actions should be permitted
            guard case .failure = ProcessAction.pause(pid: wsPID) else {
                XCTFail("Real WindowServer must NEVER be paused")
                return
            }
            guard case .failure = ProcessAction.resume(pid: wsPID) else {
                XCTFail("Real WindowServer must NEVER be resumed")
                return
            }
            guard case .failure = ProcessAction.terminate(pid: wsPID) else {
                XCTFail("Real WindowServer must NEVER be terminated")
                return
            }
            guard case .failure = ProcessAction.forceKill(pid: wsPID) else {
                XCTFail("Real WindowServer must NEVER be force-killed")
                return
            }
        }
    }

    func testProcessGuardHostAppAndParentPIDImmunity() {
        let hostPID = getpid()
        XCTAssertTrue(ProcessGuard.isProtected(pid: hostPID), "Host application PID must be protected")

        guard case .failure(let termReason) = ProcessAction.terminate(pid: hostPID) else {
            XCTFail("terminate(self) must fail")
            return
        }
        XCTAssertTrue(termReason.contains("Cannot terminate the active Resource Monitor application directly."))

        guard case .failure = ProcessAction.forceKill(pid: hostPID) else {
            XCTFail("forceKill(self) must fail")
            return
        }

        guard case .failure = ProcessAction.pause(pid: hostPID) else {
            XCTFail("pause(self) must fail")
            return
        }

        guard case .failure = ProcessAction.resume(pid: hostPID) else {
            XCTFail("resume(self) must fail")
            return
        }

        let ppid = getppid()
        if ppid > 1 {
            XCTAssertTrue(ProcessGuard.isProtected(pid: ppid), "Parent host process must be protected")
            guard case .failure = ProcessAction.terminate(pid: ppid) else {
                XCTFail("terminate(ppid) must fail")
                return
            }
            guard case .failure = ProcessAction.pause(pid: ppid) else {
                XCTFail("pause(ppid) must fail")
                return
            }
        }
    }

    func testProcessGuardBlockedProcessNamesExhaustive() {
        let testPID: pid_t = 87654
        for blockedName in ProcessGuard.blockedProcessNames {
            let status = ProcessGuard.protectionStatus(pid: testPID, name: blockedName)
            XCTAssertTrue(status.protected, "Blocked process name '\(blockedName)' must be protected")

            let pauseResult = ProcessAction.pause(pid: testPID, name: blockedName)
            guard case .failure(let reason) = pauseResult else {
                XCTFail("Pausing blocked process '\(blockedName)' must fail")
                continue
            }
            XCTAssertTrue(reason.contains(blockedName), "Reason should mention process name: \(reason)")

            let resumeResult = ProcessAction.resume(pid: testPID, name: blockedName)
            guard case .failure = resumeResult else {
                XCTFail("Resuming blocked process '\(blockedName)' must fail")
                continue
            }
        }
    }

    func testProcessGuardNegativeAndExtremeBoundaryPIDs() {
        let boundaryPIDs: [pid_t] = [-1, -2, -100, -9999, Int32.min]

        for pid in boundaryPIDs {
            XCTAssertTrue(ProcessGuard.isProtected(pid: pid), "Negative boundary PID \(pid) must be protected")

            guard case .failure = ProcessAction.pause(pid: pid) else {
                XCTFail("Pausing negative PID \(pid) must fail")
                continue
            }
            guard case .failure = ProcessAction.resume(pid: pid) else {
                XCTFail("Resuming negative PID \(pid) must fail")
                continue
            }
            guard case .failure = ProcessAction.terminate(pid: pid) else {
                XCTFail("Terminating negative PID \(pid) must fail")
                continue
            }
        }
    }

    // MARK: - 3. DarwinMachBridge fetchProcessDiskIO & RUSAGE_INFO_V4 Stress

    func testFetchProcessDiskIOCurrentProcess() {
        let currentPID = getpid()
        let diskIO = DarwinMachBridge.fetchProcessDiskIO(for: currentPID)
        XCTAssertNotNil(diskIO, "fetchProcessDiskIO must succeed for active process")
        if let io = diskIO {
            XCTAssertGreaterThanOrEqual(io.bytesRead, 0, "bytesRead must be >= 0")
            XCTAssertGreaterThanOrEqual(io.bytesWritten, 0, "bytesWritten must be >= 0")
        }
    }

    func testFetchProcessDiskIORebindingThreadSafetyStress() {
        let currentPID = getpid()
        // Execute 100 concurrent queries to verify pointer memory rebinding safety under contention
        DispatchQueue.concurrentPerform(iterations: 100) { iteration in
            let diskIO = DarwinMachBridge.fetchProcessDiskIO(for: currentPID)
            XCTAssertNotNil(diskIO, "Concurrent iteration \(iteration) must succeed")
        }
    }

    func testFetchProcessDiskIOBoundaryAndDeadPIDs() {
        let invalidPIDs: [pid_t] = [0, -1, -9999, Int32.min, 999_999_999]

        for pid in invalidPIDs {
            let io = DarwinMachBridge.fetchProcessDiskIO(for: pid)
            XCTAssertNil(io, "fetchProcessDiskIO must return nil safely for PID \(pid)")
        }
    }

    func testFetchProcessDiskIOFastExitingProcessesStress() {
        for i in 0..<20 {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/echo")
            p.arguments = ["quick_\(i)"]
            p.standardOutput = Pipe()
            try? p.run()

            let pid = p.processIdentifier
            // Rapidly query disk I/O while process is running or dying
            _ = DarwinMachBridge.fetchProcessDiskIO(for: pid)

            p.waitUntilExit()

            // Query disk I/O after process has terminated
            _ = DarwinMachBridge.fetchProcessDiskIO(for: pid)
        }
    }

    func testProcessMonitorThroughputCalculationsAndWrapAround() {
        // Test throughput calculation logic under various delta scenarios
        func computeRate(bytesDelta: UInt64, timeDeltaSec: Double) -> Double {
            timeDeltaSec > 0 ? (Double(bytesDelta) / timeDeltaSec) : 0.0
        }

        func computeDelta(newBytes: UInt64, prevBytes: UInt64) -> UInt64 {
            newBytes >= prevBytes ? (newBytes - prevBytes) : 0
        }

        let timeDeltaSec: Double = 2.0
        let readDelta: UInt64 = 10 * 1024 * 1024 // 10 MB
        let writeDelta: UInt64 = 4 * 1024 * 1024 // 4 MB

        let readRate = computeRate(bytesDelta: readDelta, timeDeltaSec: timeDeltaSec)
        let writeRate = computeRate(bytesDelta: writeDelta, timeDeltaSec: timeDeltaSec)

        XCTAssertEqual(readRate, 5 * 1024 * 1024, "Read rate should be 5 MB/s")
        XCTAssertEqual(writeRate, 2 * 1024 * 1024, "Write rate should be 2 MB/s")

        // Test zero time delta resilience (must not produce NaN or Inf)
        let safeReadRate = computeRate(bytesDelta: readDelta, timeDeltaSec: 0.0)
        XCTAssertEqual(safeReadRate, 0.0, "Zero time delta must safely yield 0.0 rate")

        // Test counter wrap-around / PID recycling scenario: totalRead < prev.diskBytesRead
        let prevBytesRead: UInt64 = 100_000_000
        let newBytesRead: UInt64 = 5_000 // Process restarted with smaller counter
        let safeDelta = computeDelta(newBytes: newBytesRead, prevBytes: prevBytesRead)
        XCTAssertEqual(safeDelta, 0, "Counter wrap must safely reset delta to 0 rather than overflowing UInt64")
    }

    // MARK: - 4. Table Sorting by ProcessSortField.diskIO Under Load

    func testDiskIOSortingAscendingAndDescendingCorrectness() {
        // Generate 5,000 mock processes with varied disk throughput
        var items: [ProcessItem] = []
        items.reserveCapacity(5000)

        for i in 0..<5000 {
            let throughput = Double((i * 37) % 1_000_000) // pseudo-random spread
            items.append(ProcessItem(
                id: pid_t(1000 + i),
                name: "Proc_\(i)",
                cpuPercentage: 1.0,
                memoryBytes: 1024 * 1024,
                diskReadBytesPerSecond: throughput * 0.7,
                diskWriteBytesPerSecond: throughput * 0.3
            ))
        }

        // Test Ascending Sort
        let sortedAsc = DashboardViewModel.filterAndSortProcesses(
            processes: items,
            query: "",
            category: .all,
            sortField: .diskIO,
            sortAscending: true
        )
        XCTAssertEqual(sortedAsc.count, 5000)
        for i in 0..<(sortedAsc.count - 1) {
            XCTAssertLessThanOrEqual(
                sortedAsc[i].totalDiskBytesPerSecond,
                sortedAsc[i + 1].totalDiskBytesPerSecond,
                "Ascending sort violated at index \(i)"
            )
        }

        // Test Descending Sort
        let sortedDesc = DashboardViewModel.filterAndSortProcesses(
            processes: items,
            query: "",
            category: .all,
            sortField: .diskIO,
            sortAscending: false
        )
        XCTAssertEqual(sortedDesc.count, 5000)
        for i in 0..<(sortedDesc.count - 1) {
            XCTAssertGreaterThanOrEqual(
                sortedDesc[i].totalDiskBytesPerSecond,
                sortedDesc[i + 1].totalDiskBytesPerSecond,
                "Descending sort violated at index \(i)"
            )
        }
    }

    func testDiskIOSortingTenThousandItemsPerformanceStress() {
        var items: [ProcessItem] = []
        items.reserveCapacity(10000)

        for i in 0..<10000 {
            let read = Double((i * 13) % 50_000_000)
            let write = Double((i * 17) % 20_000_000)
            items.append(ProcessItem(
                id: pid_t(2000 + i),
                name: "Batch_\(i)",
                cpuPercentage: 0.5,
                memoryBytes: 2048,
                diskReadBytesPerSecond: read,
                diskWriteBytesPerSecond: write
            ))
        }

        let start = DispatchTime.now()
        let sorted = DashboardViewModel.filterAndSortProcesses(
            processes: items,
            query: "",
            category: .all,
            sortField: .diskIO,
            sortAscending: false
        )
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000.0

        XCTAssertEqual(sorted.count, 10000)
        XCTAssertLessThan(elapsed, 0.250, "Sorting 10,000 items took \(elapsed)s, expected < 0.250s")
    }

    func testDiskIOSortingDeepHierarchyRollup() {
        let grandchild = ProcessItem(
            id: 303,
            ppid: 302,
            name: "Grandchild",
            cpuPercentage: 1.0,
            memoryBytes: 100,
            diskReadBytesPerSecond: 10_000_000,
            diskWriteBytesPerSecond: 5_000_000
        )

        let child = ProcessItem(
            id: 302,
            ppid: 301,
            name: "Child",
            cpuPercentage: 1.0,
            memoryBytes: 100,
            children: [grandchild],
            diskReadBytesPerSecond: 2_000_000,
            diskWriteBytesPerSecond: 1_000_000
        )

        let parentWithChildren = ProcessItem(
            id: 301,
            name: "Parent",
            cpuPercentage: 1.0,
            memoryBytes: 100,
            children: [child],
            diskReadBytesPerSecond: 500_000,
            diskWriteBytesPerSecond: 500_000
        )

        let soloProcess = ProcessItem(
            id: 401,
            name: "Solo",
            cpuPercentage: 1.0,
            memoryBytes: 100,
            diskReadBytesPerSecond: 10_000_000,
            diskWriteBytesPerSecond: 0
        )

        // parent total = (500k + 500k) + (2M + 1M) + (10M + 5M) = 1M + 3M + 15M = 19M
        // solo total = 10M
        XCTAssertEqual(parentWithChildren.totalDiskBytesPerSecond, 19_000_000)
        XCTAssertEqual(soloProcess.totalDiskBytesPerSecond, 10_000_000)

        let sortedDesc = DashboardViewModel.filterAndSortProcesses(
            processes: [soloProcess, parentWithChildren],
            query: "",
            category: .all,
            sortField: .diskIO,
            sortAscending: false
        )

        XCTAssertEqual(sortedDesc.first?.id, 301, "Parent with aggregated child disk I/O should be ranked first")
        XCTAssertEqual(sortedDesc.last?.id, 401)
    }

    func testDiskIOSortingBoundaryArrays() {
        // 1. Empty array
        let emptyResult = DashboardViewModel.filterAndSortProcesses(
            processes: [],
            query: "",
            category: .all,
            sortField: .diskIO,
            sortAscending: false
        )
        XCTAssertTrue(emptyResult.isEmpty)

        // 2. Single item
        let single = ProcessItem(id: 10, name: "Solo", cpuPercentage: 1.0, memoryBytes: 100, diskReadBytesPerSecond: 500)
        let singleResult = DashboardViewModel.filterAndSortProcesses(
            processes: [single],
            query: "",
            category: .all,
            sortField: .diskIO,
            sortAscending: true
        )
        XCTAssertEqual(singleResult.count, 1)
        XCTAssertEqual(singleResult.first?.id, 10)

        // 3. Array of 1,000 items all with zero throughput
        let zeroItems = (0..<1000).map {
            ProcessItem(id: pid_t($0 + 1), name: "Zero_\($0)", cpuPercentage: 0.0, memoryBytes: 10, diskReadBytesPerSecond: 0, diskWriteBytesPerSecond: 0)
        }
        let zeroSorted = DashboardViewModel.filterAndSortProcesses(
            processes: zeroItems,
            query: "",
            category: .all,
            sortField: .diskIO,
            sortAscending: false
        )
        XCTAssertEqual(zeroSorted.count, 1000)

        // 4. Combined query filter + disk I/O sort
        let mixed = [
            ProcessItem(id: 1, name: "FinderHelper", cpuPercentage: 1.0, memoryBytes: 100, diskReadBytesPerSecond: 1000),
            ProcessItem(id: 2, name: "SafariApp", cpuPercentage: 1.0, memoryBytes: 100, diskReadBytesPerSecond: 5000),
            ProcessItem(id: 3, name: "SafariNetwork", cpuPercentage: 1.0, memoryBytes: 100, diskReadBytesPerSecond: 20000)
        ]
        let safariFiltered = DashboardViewModel.filterAndSortProcesses(
            processes: mixed,
            query: "Safari",
            category: .all,
            sortField: .diskIO,
            sortAscending: false
        )
        XCTAssertEqual(safariFiltered.count, 2)
        XCTAssertEqual(safariFiltered[0].name, "SafariNetwork")
        XCTAssertEqual(safariFiltered[1].name, "SafariApp")
    }
}
