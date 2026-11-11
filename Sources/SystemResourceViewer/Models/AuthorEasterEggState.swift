import Foundation
import Combine

/// Easter Egg state matching PROJECT.md § Interface Contracts
public struct AuthorEasterEggState: Equatable, Sendable {
    public var clickCount: Int
    public var isUnlocked: Bool
    public var showConfetti: Bool

    public init(
        clickCount: Int = 0,
        isUnlocked: Bool = false,
        showConfetti: Bool = false
    ) {
        self.clickCount = clickCount
        self.isUnlocked = isUnlocked
        self.showConfetti = showConfetti
    }

    public static let initial = AuthorEasterEggState()
}

/// State machine governing the 7-click unlock sequence and confetti firing
public final class EasterEggStateMachine: ObservableObject, @unchecked Sendable {
    private let lock = NSLock()

    @Published public private(set) var state: AuthorEasterEggState
    @Published public private(set) var hasFiredConfettiOnce: Bool

    public init(initialState: AuthorEasterEggState = .initial, hasFiredConfettiOnce: Bool = false) {
        self.state = initialState
        self.hasFiredConfettiOnce = hasFiredConfettiOnce
    }

    public func registerClick() {
        lock.lock()
        defer { lock.unlock() }

        var newState = state
        newState.clickCount += 1

        if newState.clickCount == 7 {
            newState.isUnlocked = true
            if !hasFiredConfettiOnce {
                newState.showConfetti = true
                hasFiredConfettiOnce = true
            } else {
                newState.showConfetti = false
            }
        } else if newState.clickCount > 7 {
            newState.isUnlocked = true
            newState.showConfetti = false
        } else {
            newState.isUnlocked = false
            newState.showConfetti = false
        }

        self.state = newState
    }

    public func dismissConfetti() {
        lock.lock()
        defer { lock.unlock() }
        var newState = state
        newState.showConfetti = false
        self.state = newState
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        state = .initial
        hasFiredConfettiOnce = false
    }
}
