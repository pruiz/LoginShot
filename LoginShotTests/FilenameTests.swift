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
}
