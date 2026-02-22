import Foundation

/// Thread-safe debouncer that suppresses repeated invocations within a time window.
/// Uses actor isolation to prevent data races on the last-fire timestamp.
actor Debouncer {
    private let interval: Duration
    private let clock: ClockProtocol
    private var lastFireTime: ContinuousClock.Instant?

    /// Create a debouncer with the specified interval.
    /// - Parameters:
    ///   - seconds: Minimum interval between firings in seconds.
    ///   - clock: Clock implementation for getting current time (defaults to SystemClock).
    init(seconds: Int, clock: ClockProtocol = SystemClock()) {
        self.interval = .seconds(seconds)
        self.clock = clock
    }

    /// Returns `true` if the call should proceed (enough time has elapsed).
    /// Returns `false` if the call is within the debounce window (suppressed).
    func shouldFire() -> Bool {
        let now = clock.now()
        if let last = lastFireTime, now - last < interval {
            return false
        }
        lastFireTime = now
        return true
    }

    /// Reset the debouncer state, allowing the next call to fire.
    /// Useful for testing.
    func reset() {
        lastFireTime = nil
    }
}
