import Foundation
import Testing
@testable import SelectionBridge

@Suite struct RateLimiterTests {
    @Test func allowsRequestsUpToTheLimitWithinOneWindow() {
        let limiter = RateLimiter(maxRequestsPerWindow: 3, window: 1.0)
        let now = Date()
        #expect(limiter.allowRequest(now: now))
        #expect(limiter.allowRequest(now: now))
        #expect(limiter.allowRequest(now: now))
    }

    @Test func rejectsRequestsBeyondTheLimitWithinOneWindow() {
        let limiter = RateLimiter(maxRequestsPerWindow: 3, window: 1.0)
        let now = Date()
        #expect(limiter.allowRequest(now: now))
        #expect(limiter.allowRequest(now: now))
        #expect(limiter.allowRequest(now: now))
        #expect(!limiter.allowRequest(now: now))
    }

    @Test func allowsRequestsAgainOnceTheWindowSlidesPast() {
        let limiter = RateLimiter(maxRequestsPerWindow: 2, window: 1.0)
        let start = Date()
        #expect(limiter.allowRequest(now: start))
        #expect(limiter.allowRequest(now: start))
        #expect(!limiter.allowRequest(now: start))

        let later = start.addingTimeInterval(1.5)
        #expect(limiter.allowRequest(now: later))
    }

    @Test func oldTimestampsOutsideTheWindowDoNotCountTowardTheLimit() {
        let limiter = RateLimiter(maxRequestsPerWindow: 2, window: 1.0)
        let start = Date()
        #expect(limiter.allowRequest(now: start))
        // One old request, one new one — only the new one is inside the
        // window, so there should be room for one more.
        let later = start.addingTimeInterval(2.0)
        #expect(limiter.allowRequest(now: later))
        #expect(limiter.allowRequest(now: later))
        #expect(!limiter.allowRequest(now: later))
    }

    @Test func defaultLimiterAllowsAGenerousBurstForOrdinaryUse() {
        // The Bridge serves a handful of local, low-frequency callers —
        // this just confirms the default isn't so tight it would throttle
        // ordinary rapid-fire Selection publishing/reading.
        let limiter = RateLimiter()
        let now = Date()
        for _ in 0..<20 {
            #expect(limiter.allowRequest(now: now))
        }
    }
}
