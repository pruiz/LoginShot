@testable import LoginShot
import Foundation

/// Mock implementation of ClockProtocol for deterministic time-based tests.
final class MockClock: ClockProtocol, @unchecked Sendable {

    private var currentInstant: ContinuousClock.Instant

    init(initialTime: ContinuousClock.Instant = .now) {
        self.currentInstant = initialTime
    }

    func now() -> ContinuousClock.Instant {
        currentInstant
    }

    /// Advance the mock clock by the specified duration.
    func advance(by duration: Duration) {
        currentInstant = currentInstant.advanced(by: duration)
    }

    /// Advance the mock clock by the specified number of seconds.
    func advance(seconds: Int) {
        advance(by: .seconds(seconds))
    }

    /// Advance the mock clock by the specified number of milliseconds.
    func advance(milliseconds: Int) {
        advance(by: .milliseconds(milliseconds))
    }
}

/// Mock implementation of DateProviderProtocol for deterministic timestamp tests.
final class MockDateProvider: DateProviderProtocol, @unchecked Sendable {

    private var currentDate: Date

    init(fixedDate: Date = Date()) {
        self.currentDate = fixedDate
    }

    /// Create a MockDateProvider with a specific date from components.
    convenience init(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        // Use current timezone so formatted dates match local DateFormatter output
        components.timeZone = TimeZone.current

        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: components) ?? Date()
        self.init(fixedDate: date)
    }

    func now() -> Date {
        currentDate
    }

    /// Set the current date to a new value.
    func setDate(_ date: Date) {
        currentDate = date
    }

    /// Advance the mock date by the specified time interval.
    func advance(by interval: TimeInterval) {
        currentDate = currentDate.addingTimeInterval(interval)
    }
}
