import XCTest
@testable import SystemResourceViewer

final class SmokeTestExecutionTests: XCTestCase {

    func testSmokeTestSchedulerSimulation() async {
        let scheduler = MetricsScheduler(interval: 0.1)
        let stream = await scheduler.metricsStream()

        var count = 0
        for await snapshot in stream {
            count += 1
            XCTAssertGreaterThanOrEqual(snapshot.cpu.totalUsage, 0.0)
            XCTAssertGreaterThan(snapshot.memory.totalBytes, 0)
            XCTAssertFalse(snapshot.processes.isEmpty)

            if count >= 2 {
                break
            }
        }
        await scheduler.stop()
        XCTAssertEqual(count, 2)
    }

    func testSmokeTestBinaryProcessExecution() throws {
        // Find the built executable binary in .build
        let projectDir = FileManager.default.currentDirectoryPath
        let binaryPath = projectDir + "/.build/debug/SystemResourceViewer"

        guard FileManager.default.fileExists(atPath: binaryPath) else {
            // If binary not pre-built in current directory, skip binary subprocess test
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["--smoke-test"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0, "Smoke test process should exit with code 0")

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        XCTAssertTrue(output.contains("=== ResourceMonitor Smoke Test ==="), "Output must include smoke test banner")
        XCTAssertTrue(output.contains("=== Smoke Test Passed Successfully ==="), "Output must include smoke test success banner")
        XCTAssertTrue(output.contains("CPU:"), "Output must include CPU statistics")
        XCTAssertTrue(output.contains("RAM:"), "Output must include RAM statistics")
    }
}
