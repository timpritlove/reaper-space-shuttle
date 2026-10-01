import Foundation

/// When the native input holds the device seized: only while its owner wants it (`setActive`), so another program's
/// native input (SpaceScroll, Space Shuttle in REAPER) can take it in between (SpaceScroll ADR-0007, Space Shuttle
/// ADR-0015). Both react to the same app switch at about the same time; an open that comes before the other side has
/// let go fails with `kIOReturnExclusiveAccess` and is retried for a while. Pure state, driven by `HIDReader` on its
/// queue.
public struct SeizeClaim: Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        case none, open, close
    }

    public enum AfterFailure: Sendable, Equatable {
        /// Try again after `seconds`; pass `generation` back to `retry`.
        case retry(after: Double, generation: Int)
        case giveUp
    }

    public static let retryInterval = 0.1
    /// About two seconds of retries.
    public static let maxAttempts = 20

    public private(set) var wanted = false
    public private(set) var present = false
    public private(set) var isOpen = false
    public private(set) var attempts = 0
    /// Bumped by every change of `wanted` or `present`, so retries scheduled before it are dropped.
    public private(set) var generation = 0

    public init() {}

    public mutating func want(_ wanted: Bool) -> Action {
        guard wanted != self.wanted else { return .none }
        self.wanted = wanted
        restart()
        return settle()
    }

    public mutating func deviceAppeared() -> Action {
        present = true
        restart()
        return settle()
    }

    public mutating func deviceVanished() {
        present = false
        isOpen = false
        restart()
    }

    public mutating func opened() {
        isOpen = true
        attempts = 0
    }

    public mutating func closed() {
        isOpen = false
    }

    /// `busy`: the open failed with `kIOReturnExclusiveAccess`. Other failures are not retried.
    public mutating func openFailed(busy: Bool) -> AfterFailure {
        attempts += 1
        guard busy, attempts < Self.maxAttempts else { return .giveUp }
        return .retry(after: Self.retryInterval, generation: generation)
    }

    /// A scheduled retry is due.
    public mutating func retry(generation: Int) -> Action {
        guard generation == self.generation else { return .none }
        return settle()
    }

    private mutating func restart() {
        attempts = 0
        generation += 1
    }

    private func settle() -> Action {
        if wanted, present, !isOpen { return .open }
        if !wanted, isOpen { return .close }
        return .none
    }
}
