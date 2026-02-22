import Foundation

/// Thread-safe debouncer that suppresses repeated invocations within a time window.
/// Uses actor isolation to prevent data races on the last-fire timestamp.
actor Debouncer {
    private let interval: Duration
    private var lastFireTime: ContinuousClock.Instant?

    init(seconds: Int) {
        self.interval = .seconds(seconds)
    }

    /// Returns `true` if the call should proceed (enough time has elapsed).
    /// Returns `false` if the call is within the debounce window (suppressed).
    func shouldFire() -> Bool {
        let now = ContinuousClock.now
        if let last = lastFireTime, now - last < interval {
            return false
        }
        lastFireTime = now
        return true
    }
}
