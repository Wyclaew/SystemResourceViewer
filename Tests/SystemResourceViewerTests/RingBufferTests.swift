import XCTest
@testable import SystemResourceViewer

final class RingBufferTests: XCTestCase {

    func testEmptyBufferInitialization() {
        let buffer = RingBuffer<Int>(capacity: 5)
        XCTAssertEqual(buffer.capacity, 5)
        XCTAssertEqual(buffer.count, 0)
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.toArray(), [])
    }

    func testPrepopulatedBufferInitialization() {
        let buffer = RingBuffer<Double>(capacity: 60, initialElement: 0.0)
        XCTAssertEqual(buffer.capacity, 60)
        XCTAssertEqual(buffer.count, 60)
        XCTAssertFalse(buffer.isEmpty)
        XCTAssertEqual(buffer[0], 0.0)
        XCTAssertEqual(buffer[59], 0.0)
        XCTAssertEqual(buffer.elements.count, 60)
    }

    func testSequenceInitializationWithinCapacity() {
        let buffer = RingBuffer<Int>(capacity: 5, elements: [10, 20, 30])
        XCTAssertEqual(buffer.capacity, 5)
        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.toArray(), [10, 20, 30])
    }

    func testSequenceInitializationExceedingCapacity() {
        let buffer = RingBuffer<Int>(capacity: 3, elements: [1, 2, 3, 4, 5])
        XCTAssertEqual(buffer.capacity, 3)
        XCTAssertEqual(buffer.count, 3)
        // Only the last 3 elements should be retained
        XCTAssertEqual(buffer.toArray(), [3, 4, 5])
    }

    func testAppendWithinCapacity() {
        var buffer = RingBuffer<String>(capacity: 4)
        buffer.append("Alpha")
        buffer.append("Beta")
        buffer.append("Gamma")

        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer[0], "Alpha")
        XCTAssertEqual(buffer[1], "Beta")
        XCTAssertEqual(buffer[2], "Gamma")
        XCTAssertEqual(buffer.toArray(), ["Alpha", "Beta", "Gamma"])
    }

    func testAppendExceedingCapacityOverwritesOldest() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(1)
        buffer.append(2)
        buffer.append(3)
        XCTAssertEqual(buffer.toArray(), [1, 2, 3])

        // Overwrites oldest element (1)
        buffer.append(4)
        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.toArray(), [2, 3, 4])
        XCTAssertEqual(buffer[0], 2)
        XCTAssertEqual(buffer[1], 3)
        XCTAssertEqual(buffer[2], 4)

        // Overwrites next oldest element (2)
        buffer.append(5)
        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.toArray(), [3, 4, 5])

        buffer.append(6)
        XCTAssertEqual(buffer.toArray(), [4, 5, 6])
    }

    func testArrayProjection() {
        var buffer = RingBuffer<Double>(capacity: 4)
        buffer.append(10.5)
        buffer.append(20.5)

        XCTAssertEqual(buffer.elements, [10.5, 20.5])
        XCTAssertEqual(buffer.toArray(), [10.5, 20.5])

        buffer.append(30.5)
        buffer.append(40.5)
        buffer.append(50.5) // Overwrites 10.5

        XCTAssertEqual(buffer.elements, [20.5, 30.5, 40.5, 50.5])
        XCTAssertEqual(buffer.toArray(), [20.5, 30.5, 40.5, 50.5])
    }

    func testRandomAccessCollectionOperations() {
        var buffer = RingBuffer<Int>(capacity: 5)
        for i in 1...8 {
            buffer.append(i)
        }
        // Buffer now holds [4, 5, 6, 7, 8]
        XCTAssertEqual(buffer.count, 5)
        XCTAssertEqual(buffer.first, 4)
        XCTAssertEqual(buffer.last, 8)

        // Iteration
        let doubled = buffer.map { $0 * 2 }
        XCTAssertEqual(doubled, [8, 10, 12, 14, 16])

        // Reduction
        let sum = buffer.reduce(0, +)
        XCTAssertEqual(sum, 30)

        // Filtering
        let evens = buffer.filter { $0 % 2 == 0 }
        XCTAssertEqual(evens, [4, 6, 8])

        // Prefix
        let prefixTwo = Array(buffer.prefix(2))
        XCTAssertEqual(prefixTwo, [4, 5])
    }

    func testRemoveAllPreservesCapacity() {
        var buffer = RingBuffer<Int>(capacity: 5)
        buffer.append(1)
        buffer.append(2)
        XCTAssertEqual(buffer.count, 2)

        buffer.removeAll()
        XCTAssertEqual(buffer.count, 0)
        XCTAssertEqual(buffer.capacity, 5)
        XCTAssertTrue(buffer.isEmpty)

        buffer.append(99)
        XCTAssertEqual(buffer.count, 1)
        XCTAssertEqual(buffer[0], 99)
    }

    func testEquatableConformance() {
        var b1 = RingBuffer<Int>(capacity: 3)
        var b2 = RingBuffer<Int>(capacity: 3)

        b1.append(1)
        b1.append(2)
        b2.append(1)
        b2.append(2)
        XCTAssertEqual(b1, b2)

        b1.append(3)
        b2.append(4)
        XCTAssertNotEqual(b1, b2)

        let b3 = RingBuffer<Int>(capacity: 5)
        XCTAssertNotEqual(b1, b3)
    }

    func testHighVolumeAppendPerformance() {
        var buffer = RingBuffer<Int>(capacity: 60)
        let totalItems = 100_000

        let start = DispatchTime.now()
        for i in 0..<totalItems {
            buffer.append(i)
        }
        let end = DispatchTime.now()

        let elapsedMs = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
        XCTAssertEqual(buffer.count, 60)
        XCTAssertEqual(buffer.first, totalItems - 60)
        XCTAssertEqual(buffer.last, totalItems - 1)
        // 100k appends in RingBuffer should execute in under 50ms
        XCTAssertLessThan(elapsedMs, 50.0, "100k appends took \(elapsedMs) ms")
    }
}
