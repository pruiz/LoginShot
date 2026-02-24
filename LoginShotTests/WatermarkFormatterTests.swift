import XCTest
@testable import LoginShot

final class WatermarkFormatterTests: XCTestCase {
    func testTimestampUsesProvidedFormat() {
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 24
        components.hour = 13
        components.minute = 5
        components.second = 9
        components.timeZone = TimeZone(secondsFromGMT: 0)
        let date = Calendar(identifier: .gregorian).date(from: components)!

        let output = WatermarkFormatter.timestamp(date: date, format: "yyyy/MM/dd HH:mm:ss")

        XCTAssertEqual(output, "2026/02/24 13:05:09")
    }

    func testTimestampFallsBackForEmptyFormat() {
        let date = Date(timeIntervalSince1970: 0)

        let output = WatermarkFormatter.timestamp(date: date, format: "   ")

        XCTAssertFalse(output.isEmpty)
    }

    func testTimestampFallsBackForLiteralFormat() {
        let date = Date(timeIntervalSince1970: 0)

        let output = WatermarkFormatter.timestamp(date: date, format: "invalid-format")

        XCTAssertNotEqual(output, "invalid-format")
    }

    func testTextCombinesHostnameAndTimestamp() {
        let date = Date(timeIntervalSince1970: 0)

        let output = WatermarkFormatter.text(hostname: "MyMac", date: date, format: "yyyy")

        XCTAssertEqual(output, "MyMac 1970")
    }
}
