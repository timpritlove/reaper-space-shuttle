import Testing
@testable import SpaceMouseKit

struct SeizeClaimTests {
    @Test func opensOnlyWhenWantedAndPresent() {
        var claim = SeizeClaim()
        #expect(claim.want(true) == .none)
        #expect(claim.deviceAppeared() == .open)

        var later = SeizeClaim()
        #expect(later.deviceAppeared() == .none)
        #expect(later.want(true) == .open)
    }

    @Test func letsGoWhenNoLongerWanted() {
        var claim = SeizeClaim()
        _ = claim.deviceAppeared()
        _ = claim.want(true)
        claim.opened()
        #expect(claim.want(false) == .close)
        claim.closed()
        #expect(claim.want(true) == .open)
    }

    @Test func repeatedWishesChangeNothing() {
        var claim = SeizeClaim()
        _ = claim.deviceAppeared()
        _ = claim.want(true)
        claim.opened()
        #expect(claim.want(true) == .none)
    }

    @Test func busyIsRetriedForAWhileThenGivenUp() {
        var claim = SeizeClaim()
        _ = claim.deviceAppeared()
        _ = claim.want(true)
        for _ in 1..<SeizeClaim.maxAttempts {
            guard case .retry(_, let generation) = claim.openFailed(busy: true) else {
                Issue.record("expected a retry")
                return
            }
            #expect(claim.retry(generation: generation) == .open)
        }
        #expect(claim.openFailed(busy: true) == .giveUp)
    }

    @Test func otherFailuresAreNotRetried() {
        var claim = SeizeClaim()
        _ = claim.deviceAppeared()
        _ = claim.want(true)
        #expect(claim.openFailed(busy: false) == .giveUp)
    }

    @Test func aRetryAfterLettingGoIsDropped() {
        var claim = SeizeClaim()
        _ = claim.deviceAppeared()
        _ = claim.want(true)
        guard case .retry(_, let generation) = claim.openFailed(busy: true) else {
            Issue.record("expected a retry")
            return
        }
        #expect(claim.want(false) == .none)
        #expect(claim.retry(generation: generation) == .none)
    }

    @Test func aNewWishStartsAFreshRoundOfRetries() {
        var claim = SeizeClaim()
        _ = claim.deviceAppeared()
        _ = claim.want(true)
        for _ in 1..<SeizeClaim.maxAttempts { _ = claim.openFailed(busy: true) }
        _ = claim.want(false)
        #expect(claim.want(true) == .open)
        #expect(claim.openFailed(busy: true) != .giveUp)
    }

    @Test func vanishingClosesTheClaim() {
        var claim = SeizeClaim()
        _ = claim.deviceAppeared()
        _ = claim.want(true)
        claim.opened()
        claim.deviceVanished()
        #expect(!claim.isOpen)
        #expect(claim.deviceAppeared() == .open)
    }
}
