import XCTest
@testable import LoginShot

/// Deterministic tests for Debouncer using MockClock for time control.
final class DebouncerDeterministicTests: XCTestCase {

    private var mockClock: MockClock!

    override func setUp() {
        super.setUp()
        mockClock = MockClock()
    }

    override func tearDown() {
        mockClock = nil
        super.tearDown()
    }

    // MARK: - Basic Behavior with Mock Clock

    func testFirstCallAlwaysFiresWithMockClock() async {
        let debouncer = Debouncer(seconds: 5, clock: mockClock)
        let result = await debouncer.shouldFire()
        XCTAssertTrue(result, "First call should always fire")
    }

    func testSuppressedWithinIntervalWithMockClock() async {
        let debouncer = Debouncer(seconds: 5, clock: mockClock)

        let first = await debouncer.shouldFire()
        XCTAssertTrue(first)

        // Advance time by less than interval
        mockClock.advance(seconds: 4)

        let second = await debouncer.shouldFire()
        XCTAssertFalse(second, "Should be suppressed within interval")
    }

    func testFiresAfterExactInterval() async {
        let debouncer = Debouncer(seconds: 5, clock: mockClock)

        let first = await debouncer.shouldFire()
        XCTAssertTrue(first)

        // Advance time by exactly the interval
        mockClock.advance(seconds: 5)

        let second = await debouncer.shouldFire()
        XCTAssertTrue(second, "Should fire after exact interval")
    }

    func testFiresJustAfterInterval() async {
        let debouncer = Debouncer(seconds: 3, clock: mockClock)

        let first = await debouncer.shouldFire()
        XCTAssertTrue(first)

        // Advance time by just over the interval (1ms over)
        mockClock.advance(by: .seconds(3) + .milliseconds(1))

        let second = await debouncer.shouldFire()
        XCTAssertTrue(second, "Should fire just after interval")
    }

    func testSuppressedJustBeforeInterval() async {
        let debouncer = Debouncer(seconds: 3, clock: mockClock)

        let first = await debouncer.shouldFire()
        XCTAssertTrue(first)

        // Advance time by just under the interval (1ms under)
        mockClock.advance(by: .seconds(3) - .milliseconds(1))

        let second = await debouncer.shouldFire()
        XCTAssertFalse(second, "Should be suppressed just before interval")
    }

    func testMultipleIntervalCycles() async {
        let debouncer = Debouncer(seconds: 2, clock: mockClock)
        var results: [Bool] = []

        // Cycle 1: Fire
        results.append(await debouncer.shouldFire())
        XCTAssertTrue(results.last!)

        // Still within interval
        mockClock.advance(seconds: 1)
        results.append(await debouncer.shouldFire())
        XCTAssertFalse(results.last!)

        // Cycle 2: Fire after interval
        mockClock.advance(seconds: 2)
        results.append(await debouncer.shouldFire())
        XCTAssertTrue(results.last!)

        // Still within new interval
        mockClock.advance(milliseconds: 500)
        results.append(await debouncer.shouldFire())
        XCTAssertFalse(results.last!)

        // Cycle 3: Fire after interval
        mockClock.advance(seconds: 2)
        results.append(await debouncer.shouldFire())
        XCTAssertTrue(results.last!)

        XCTAssertEqual(results, [true, false, true, false, true])
    }

    func testResetAllowsImmediateFire() async {
        let debouncer = Debouncer(seconds: 10, clock: mockClock)

        let first = await debouncer.shouldFire()
        XCTAssertTrue(first)

        // Without advancing time, second call would be suppressed
        let second = await debouncer.shouldFire()
        XCTAssertFalse(second)

        // Reset the debouncer
        await debouncer.reset()

        // Now it should fire again
        let third = await debouncer.shouldFire()
        XCTAssertTrue(third, "Should fire immediately after reset")
    }

    func testZeroIntervalAlwaysFiresWithMockClock() async {
        let debouncer = Debouncer(seconds: 0, clock: mockClock)

        // Multiple calls without advancing time should all fire
        for i in 0..<5 {
            let result = await debouncer.shouldFire()
            XCTAssertTrue(result, "Call \(i) should fire with zero interval")
        }
    }

    func testLongIntervalSuppression() async {
        let debouncer = Debouncer(seconds: 3600, clock: mockClock) // 1 hour

        let first = await debouncer.shouldFire()
        XCTAssertTrue(first)

        // Advance by 59 minutes - still suppressed
        mockClock.advance(seconds: 59 * 60)
        let second = await debouncer.shouldFire()
        XCTAssertFalse(second)

        // Advance to exactly 1 hour total - should fire
        mockClock.advance(seconds: 60)
        let third = await debouncer.shouldFire()
        XCTAssertTrue(third)
    }
}
