import Foundation

// MARK: - Clock Protocol

/// Protocol for getting current time instant (test seam for deterministic debounce tests).
protocol ClockProtocol: Sendable {
    func now() -> ContinuousClock.Instant
}

/// Production implementation using the real system clock.
struct SystemClock: ClockProtocol, Sendable {
    func now() -> ContinuousClock.Instant {
        ContinuousClock.now
    }
}

// MARK: - Date Provider Protocol

/// Protocol for getting current Date (test seam for deterministic timestamp tests).
protocol DateProviderProtocol: Sendable {
    func now() -> Date
}

/// Production implementation using the real system date.
struct SystemDateProvider: DateProviderProtocol, Sendable {
    func now() -> Date {
        Date()
    }
}
