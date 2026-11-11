import XCTest
@testable import SystemResourceViewer

final class GPUBoundaryTests: XCTestCase {

    func testZeroPercentGPUIdleState() {
        let idle = GPUMetricsContract(
            deviceUtilization: 0.0,
            rendererUtilization: 0.0,
            tilerUtilization: 0.0
        )
        XCTAssertEqual(idle.clampedDeviceUtilization, 0.0)
        XCTAssertEqual(idle.deviceUtilization, 0.0)
        XCTAssertEqual(idle.rendererUtilization, 0.0)
        XCTAssertEqual(idle.tilerUtilization, 0.0)
    }

    func testOneHundredPercentGPUSaturation() {
        let maxed = GPUMetricsContract(
            deviceUtilization: 100.0,
            rendererUtilization: 100.0,
            tilerUtilization: 100.0
        )
        XCTAssertEqual(maxed.clampedDeviceUtilization, 100.0)
    }

    func testZeroAllocatedVRAMProtection() {
        let metrics = GPUMetricsContract(
            allocatedVRAMBytes: 0,
            inUseVRAMBytes: 0
        )
        // Must return 0.0 without crash
        XCTAssertEqual(metrics.vramUsagePercentage, 0.0)
    }

    func testInUseVRAMExceedingAllocatedClamping() {
        let metrics = GPUMetricsContract(
            allocatedVRAMBytes: 1000,
            inUseVRAMBytes: 2000
        )
        // Clamped at 100.0%
        XCTAssertEqual(metrics.vramUsagePercentage, 100.0)
    }

    func testNegativeAndOverflowUtilizationClamping() {
        let neg = GPUMetricsContract(deviceUtilization: -50.0)
        XCTAssertEqual(neg.clampedDeviceUtilization, 0.0)

        let over = GPUMetricsContract(deviceUtilization: 250.0)
        XCTAssertEqual(over.clampedDeviceUtilization, 100.0)
    }
}
