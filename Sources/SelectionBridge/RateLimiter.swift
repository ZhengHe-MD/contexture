import Foundation

/// A simple global rate limiter for the Bridge's socket
/// (docs/architecture/selection-bridge.md "Local security boundary":
/// "Rate-limit reads and cap payload size" — the payload cap already
/// exists in `HTTPRequestParser.maxBodyBytes`; this is the other half).
///
/// This is a local, single-user IPC channel: the threat model is a
/// misbehaving caller (a stuck retry loop, a bug in some future Adapter)
/// hammering the Bridge, not a remote attacker — socket permissions
/// (mode 0600) already exclude that. A Unix domain socket carries no
/// per-connection identity worth rate-limiting individually without OS-
/// level work this doesn't need, so a single global sliding-window
/// counter is enough.
public final class RateLimiter {
    private let maxRequestsPerWindow: Int
    private let window: TimeInterval
    private let lock = NSLock()
    private var requestTimestamps: [Date] = []

    public init(maxRequestsPerWindow: Int = 50, window: TimeInterval = 1.0) {
        self.maxRequestsPerWindow = maxRequestsPerWindow
        self.window = window
    }

    /// `now` is injectable so this is deterministically testable without
    /// sleeping real wall-clock time.
    public func allowRequest(now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let cutoff = now.addingTimeInterval(-window)
        requestTimestamps.removeAll { $0 < cutoff }
        guard requestTimestamps.count < maxRequestsPerWindow else { return false }
        requestTimestamps.append(now)
        return true
    }
}
