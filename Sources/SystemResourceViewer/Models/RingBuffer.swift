import Foundation

/// A fixed-capacity circular ring buffer with O(1) append, RandomAccessCollection conformance, and Sendable safety.
/// Used for historical telemetry time-series to eliminate array memory reallocation churn.
public struct RingBuffer<Element: Sendable>: RandomAccessCollection, Sendable {
    private var storage: [Element]
    private var head: Int = 0
    public let capacity: Int
    public private(set) var count: Int = 0

    /// Creates an empty ring buffer with the specified fixed capacity.
    public init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer capacity must be strictly positive")
        self.capacity = capacity
        self.storage = []
        self.storage.reserveCapacity(capacity)
        self.head = 0
        self.count = 0
    }

    /// Creates a pre-populated ring buffer filled with a repeating initial element.
    public init(capacity: Int, initialElement: Element) {
        precondition(capacity > 0, "RingBuffer capacity must be strictly positive")
        self.capacity = capacity
        self.storage = Array(repeating: initialElement, count: capacity)
        self.head = 0
        self.count = capacity
    }

    /// Creates a ring buffer initialized with elements from an existing sequence.
    public init<S: Sequence>(capacity: Int, elements: S) where S.Element == Element {
        precondition(capacity > 0, "RingBuffer capacity must be strictly positive")
        self.capacity = capacity
        self.storage = []
        self.storage.reserveCapacity(capacity)
        self.head = 0
        self.count = 0
        for elem in elements {
            self.append(elem)
        }
    }

    /// Appends a new element in O(1) time. When capacity is exceeded, overwrites the oldest element.
    public mutating func append(_ element: Element) {
        if count < capacity {
            storage.append(element)
            count += 1
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    /// Clears all elements from the ring buffer.
    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        head = 0
        count = 0
    }

    // MARK: - RandomAccessCollection Conformance

    public var startIndex: Int { 0 }
    public var endIndex: Int { count }

    public func index(after i: Int) -> Int {
        i + 1
    }

    public func index(before i: Int) -> Int {
        i - 1
    }

    public subscript(position: Int) -> Element {
        precondition(position >= 0 && position < count, "RingBuffer index out of bounds: \(position) for count \(count)")
        if count < capacity {
            return storage[position]
        } else {
            let actualIndex = (head + position) % capacity
            return storage[actualIndex]
        }
    }

    // MARK: - Array Projection

    /// Projects the ring buffer elements chronologically into a standard Swift Array.
    public var elements: [Element] {
        toArray()
    }

    /// Returns an ordered Array containing the buffer's elements in chronological order.
    public func toArray() -> [Element] {
        if count < capacity {
            return Array(storage.prefix(count))
        }
        var result: [Element] = []
        result.reserveCapacity(capacity)
        for i in 0..<count {
            result.append(self[i])
        }
        return result
    }
}

// MARK: - Equatable Conformance

extension RingBuffer: Equatable where Element: Equatable {
    public static func == (lhs: RingBuffer<Element>, rhs: RingBuffer<Element>) -> Bool {
        guard lhs.capacity == rhs.capacity && lhs.count == rhs.count else {
            return false
        }
        for i in 0..<lhs.count {
            if lhs[i] != rhs[i] {
                return false
            }
        }
        return true
    }
}

// MARK: - CustomStringConvertible

extension RingBuffer: CustomStringConvertible {
    public var description: String {
        "RingBuffer(capacity: \(capacity), count: \(count), elements: \(toArray()))"
    }
}
