import XCTest
@testable import SystemResourceViewer

final class ProcessExecutionControlTests: XCTestCase {
    func testProcessGuardProtectsSystemProcesses() {
        XCTAssertTrue(ProcessGuard.isProtected(pid: 0), "Kernel PID 0 must be protected")
        XCTAssertTrue(ProcessGuard.isProtected(pid: 1), "launchd PID 1 must be protected")
        XCTAssertTrue(ProcessGuard.isProtected(pid: getpid()), "Own process must be protected")
        XCTAssertTrue(ProcessGuard.isProtected(pid: 99999, name: "launchd"), "launchd name must be protected")
        XCTAssertTrue(ProcessGuard.isProtected(pid: 99999, name: "kernel_task"), "kernel_task must be protected")
        XCTAssertTrue(ProcessGuard.isProtected(pid: 99999, name: "WindowServer"), "WindowServer must be protected")
    }

    func testProcessActionRejectsProtectedProcesses() {
        let pausePID1 = ProcessAction.pause(pid: 1, name: "launchd")
        XCTAssertEqual(pausePID1, .failure("Cannot terminate system initialization process (PID 1)."))

        let resumePID1 = ProcessAction.resume(pid: 1, name: "launchd")
        XCTAssertEqual(resumePID1, .failure("Cannot terminate system initialization process (PID 1)."))

        let pauseSelf = ProcessAction.pause(pid: getpid(), name: "self")
        XCTAssertEqual(pauseSelf, .failure("Cannot terminate the active Resource Monitor application directly."))
    }

    func testPauseAndResumeOnRealSubprocess() throws {
        // Spawn a real child process using /bin/sleep 30
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()

        let childPID = process.processIdentifier
        XCTAssertGreaterThan(childPID, 0, "Child process must have a valid PID")

        // Verify child is alive
        XCTAssertEqual(kill(childPID, 0), 0, "Child process must be running")

        // Test Pause (SIGSTOP)
        let pauseResult = ProcessAction.pause(pid: childPID, name: "sleep")
        XCTAssertEqual(pauseResult, .success, "Pausing child process should succeed")

        // Check process still exists (kill(pid, 0) == 0)
        XCTAssertEqual(kill(childPID, 0), 0, "Suspended child process still exists in process table")

        // Test Resume (SIGCONT)
        let resumeResult = ProcessAction.resume(pid: childPID, name: "sleep")
        XCTAssertEqual(resumeResult, .success, "Resuming child process should succeed")
        XCTAssertEqual(kill(childPID, 0), 0, "Resumed child process is alive")

        // Clean up child process
        process.terminate()
        process.waitUntilExit()
    }
}
