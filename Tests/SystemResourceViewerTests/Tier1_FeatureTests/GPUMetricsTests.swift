import XCTest
@testable import SystemResourceViewer

final class GPUMetricsTests: XCTestCase {

    func testGPUMetricsDefaultEmpty() {
        let metrics = GPUMetricsContract.empty
        XCTAssertEqual(metrics.deviceUtilization, 0.0)
        XCTAssertEqual(metrics.rendererUtilization, 0.0)
        XCTAssertEqual(metrics.tilerUtilization, 0.0)
        XCTAssertEqual(metrics.allocatedVRAMBytes, 0)
        XCTAssertEqual(metrics.inUseVRAMBytes, 0)
        XCTAssertEqual(metrics.coreCount, 0)
        XCTAssertEqual(metrics.modelName, "Apple Silicon GPU")
    }

    func testGPUMetricsCustomInitialization() {
        let metrics = GPUMetricsContract(
            deviceUtilization: 34.5,
            rendererUtilization: 28.0,
            tilerUtilization: 12.5,
            allocatedVRAMBytes: 8 * 1024 * 1024 * 1024,
            inUseVRAMBytes: 2 * 1024 * 1024 * 1024,
            coreCount: 16,
            modelName: "Apple M3 Pro"
        )
        XCTAssertEqual(metrics.deviceUtilization, 34.5)
        XCTAssertEqual(metrics.rendererUtilization, 28.0)
        XCTAssertEqual(metrics.tilerUtilization, 12.5)
        XCTAssertEqual(metrics.allocatedVRAMBytes, 8 * 1024 * 1024 * 1024)
        XCTAssertEqual(metrics.inUseVRAMBytes, 2 * 1024 * 1024 * 1024)
        XCTAssertEqual(metrics.coreCount, 16)
        XCTAssertEqual(metrics.modelName, "Apple M3 Pro")
    }

    func testGPUUtilizationClamping() {
        let normal = GPUMetricsContract(deviceUtilization: 65.0)
        XCTAssertEqual(normal.clampedDeviceUtilization, 65.0)

        let negative = GPUMetricsContract(deviceUtilization: -10.0)
        XCTAssertEqual(negative.clampedDeviceUtilization, 0.0)

        let over = GPUMetricsContract(deviceUtilization: 145.0)
        XCTAssertEqual(over.clampedDeviceUtilization, 100.0)
    }

    func testGPUVRAMUsagePercentage() {
        let metrics = GPUMetricsContract(
            allocatedVRAMBytes: 4 * 1024 * 1024 * 1024,
            inUseVRAMBytes: 1 * 1024 * 1024 * 1024
        )
        // 1 GB / 4 GB = 25.0%
        XCTAssertEqual(metrics.vramUsagePercentage, 25.0, accuracy: 0.01)
    }

    func testGPUMetricsEquatableAndSendable() {
        let m1 = GPUMetricsContract(deviceUtilization: 10.0, coreCount: 8)
        let m2 = GPUMetricsContract(deviceUtilization: 10.0, coreCount: 8)
        let m3 = GPUMetricsContract(deviceUtilization: 20.0, coreCount: 8)

        XCTAssertEqual(m1, m2)
        XCTAssertNotEqual(m1, m3)
    }
}
