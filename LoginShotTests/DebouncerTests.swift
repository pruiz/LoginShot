import XCTest
@testable import LoginShot

final class DebouncerTests: XCTestCase {

    func testFirstCallAlwaysFires() async {
        let debouncer = Debouncer(seconds: 3)
        let result = await debouncer.shouldFire()
        XCTAssertTrue(result, "First call should always fire")
    }

    func testImmediateSecondCallIsSuppressed() async {
        let debouncer = Debouncer(seconds: 3)
        let first = await debouncer.shouldFire()
        let second = await debouncer.shouldFire()
        XCTAssertTrue(first)
        XCTAssertFalse(second, "Immediate second call should be suppressed")
    }

    func testFiresAgainAfterInterval() async throws {
        let debouncer = Debouncer(seconds: 1)
        let first = await debouncer.shouldFire()
        XCTAssertTrue(first)

        // Wait beyond the debounce interval
        try await Task.sleep(for: .milliseconds(1100))

        let second = await debouncer.shouldFire()
        XCTAssertTrue(second, "Should fire again after debounce interval elapses")
    }

    func testZeroIntervalAlwaysFires() async {
        let debouncer = Debouncer(seconds: 0)
        let first = await debouncer.shouldFire()
        let second = await debouncer.shouldFire()
        let third = await debouncer.shouldFire()
        XCTAssertTrue(first)
        XCTAssertTrue(second)
        XCTAssertTrue(third)
    }

    func testMultipleRapidCallsSuppressed() async {
        let debouncer = Debouncer(seconds: 5)
        var results: [Bool] = []
        for _ in 0..<5 {
            let result = await debouncer.shouldFire()
            results.append(result)
        }
        XCTAssertEqual(results.filter { $0 }.count, 1,
                       "Only the first of 5 rapid calls should fire")
    }
}
