import XCTest
@testable import LoginShot

@MainActor
final class FilenameTests: XCTestCase {

    func testFilenameFormatSessionOpen() {
        let filename = AppDelegate.makeFilename(event: .sessionOpen, format: "jpg")

        // Pattern: YYYY-MM-DDTHH-mm-ss-session-open.jpg
        XCTAssertTrue(filename.hasSuffix("-session-open.jpg"),
                      "Filename should end with event and format: got \(filename)")
        XCTAssertTrue(filename.contains("T"),
                      "Filename should contain T separator: got \(filename)")
    }

    func testFilenameFormatUnlock() {
        let filename = AppDelegate.makeFilename(event: .unlock, format: "jpg")
        XCTAssertTrue(filename.hasSuffix("-unlock.jpg"))
    }

    func testFilenameFormatManual() {
        let filename = AppDelegate.makeFilename(event: .manual, format: "jpg")
        XCTAssertTrue(filename.hasSuffix("-manual.jpg"))
    }

    func testFilenameTimestampFormat() {
        let filename = AppDelegate.makeFilename(event: .sessionOpen, format: "jpg")

        // Extract the timestamp portion (everything before the event tag)
        // Expected: 2026-02-22T02-30-00-session-open.jpg
        let parts = filename.components(separatedBy: "-session-open")
        XCTAssertEqual(parts.count, 2, "Should split into timestamp and extension")

        let timestamp = parts[0]
        // Verify format: YYYY-MM-DDTHH-mm-ss (19 chars)
        XCTAssertEqual(timestamp.count, 19,
                       "Timestamp should be 19 chars (YYYY-MM-DDTHH-mm-ss): got '\(timestamp)'")
    }

    func testFilenameDoesNotContainColons() {
        let filename = AppDelegate.makeFilename(event: .unlock, format: "jpg")
        XCTAssertFalse(filename.contains(":"),
                       "Filename should not contain colons (filesystem-unsafe)")
    }

    func testFilenameDoesNotContainSpaces() {
        let filename = AppDelegate.makeFilename(event: .unlock, format: "jpg")
        XCTAssertFalse(filename.contains(" "),
                       "Filename should not contain spaces")
    }

    // MARK: - Deterministic Tests with Fixed Date

    func testMakeFilenameWithFixedDateUTC() {
        let date = makeDate(year: 2024, month: 6, day: 15, hour: 14, minute: 30, second: 0)
        let filename = AppDelegate.makeFilename(event: .sessionOpen, format: "jpg", date: date)

        XCTAssertEqual(filename, "2024-06-15T14-30-00-session-open.jpg",
                       "Filename should use the exact provided date")
    }

    func testMakeFilenameWithFixedDateMidnight() {
        let date = makeDate(year: 2025, month: 1, day: 1, hour: 0, minute: 0, second: 0)
        let filename = AppDelegate.makeFilename(event: .unlock, format: "png", date: date)

        XCTAssertEqual(filename, "2025-01-01T00-00-00-unlock.png",
                       "Filename should handle midnight correctly")
    }

    func testMakeFilenameWithFixedDateEndOfDay() {
        let date = makeDate(year: 2024, month: 12, day: 31, hour: 23, minute: 59, second: 59)
        let filename = AppDelegate.makeFilename(event: .manual, format: "jpg", date: date)

        XCTAssertEqual(filename, "2024-12-31T23-59-59-manual.jpg",
                       "Filename should handle end of day correctly")
    }

    func testMakeFilenameAllEventTypesWithFixedDate() {
        let date = makeDate(year: 2024, month: 7, day: 4, hour: 12, minute: 0, second: 0)

        let sessionOpenFilename = AppDelegate.makeFilename(event: .sessionOpen, format: "jpg", date: date)
        let unlockFilename = AppDelegate.makeFilename(event: .unlock, format: "jpg", date: date)
        let manualFilename = AppDelegate.makeFilename(event: .manual, format: "jpg", date: date)

        XCTAssertEqual(sessionOpenFilename, "2024-07-04T12-00-00-session-open.jpg")
        XCTAssertEqual(unlockFilename, "2024-07-04T12-00-00-unlock.jpg")
        XCTAssertEqual(manualFilename, "2024-07-04T12-00-00-manual.jpg")
    }

    // MARK: - Helper

    /// Create a date with specific components in the current/local timezone.
    /// This matches how `makeFilename` formats dates (using local timezone).
    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        // Use current timezone (same as DateFormatter default in makeFilename)
        components.timeZone = TimeZone.current
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}
