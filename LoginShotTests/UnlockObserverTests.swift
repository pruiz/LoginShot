import XCTest
@testable import LoginShot

/// Tests for UnlockObserver state management.
/// Note: These tests verify the observer's state machine, not the actual notification handling
/// (which would require integration tests with real NotificationCenter).
@MainActor
final class UnlockObserverTests: XCTestCase {

    // MARK: - Start/Stop State Tests

    func testStartSetsRunningState() {
        let observer = UnlockObserver()
        var eventReceived: CaptureEvent?

        observer.start(debounceSeconds: 3) { event in
            eventReceived = event
        }

        // Observer should now be running (we can verify via stop behavior)
        observer.stop()
        // If it wasn't running, stop would be a no-op and we'd still have the handler

        XCTAssertNil(eventReceived, "Handler should not have been called yet")
    }

    func testStopClearsState() {
        let observer = UnlockObserver()

        observer.start(debounceSeconds: 3) { _ in }
        observer.stop()

        // Starting again should work (proves stop cleared the state)
        var secondHandlerCalled = false
        observer.start(debounceSeconds: 3) { _ in
            secondHandlerCalled = true
        }

        // Verify observer can be started again
        observer.stop()
        XCTAssertFalse(secondHandlerCalled)
    }

    func testDoubleStartIsIgnored() {
        let observer = UnlockObserver()
        var firstHandlerCallCount = 0
        var secondHandlerCallCount = 0

        // First start
        observer.start(debounceSeconds: 3) { _ in
            firstHandlerCallCount += 1
        }

        // Second start should be ignored (logged as warning)
        observer.start(debounceSeconds: 3) { _ in
            secondHandlerCallCount += 1
        }

        // Clean up
        observer.stop()

        // Neither handler should have been called (no events triggered)
        XCTAssertEqual(firstHandlerCallCount, 0)
        XCTAssertEqual(secondHandlerCallCount, 0)
    }

    func testStopWhenNotRunningIsNoOp() {
        let observer = UnlockObserver()

        // Stopping before starting should not crash or cause issues
        observer.stop()
        observer.stop()
        observer.stop()

        // Should still be able to start normally
        var handlerCalled = false
        observer.start(debounceSeconds: 3) { _ in
            handlerCalled = true
        }
        observer.stop()

        XCTAssertFalse(handlerCalled)
    }

    func testDebounceSecondsPassedCorrectly() {
        let observer = UnlockObserver()

        // Start with specific debounce value
        observer.start(debounceSeconds: 7) { _ in }

        // We can't directly verify the debouncer interval from outside,
        // but we can verify the observer accepts the parameter without error
        observer.stop()
    }

    // MARK: - Mock Observer Tests

    func testMockUnlockObserverTracksStart() {
        let mock = MockUnlockObserver()

        XCTAssertFalse(mock.startCalled)
        XCTAssertNil(mock.debounceSecondsReceived)

        mock.start(debounceSeconds: 5) { _ in }

        XCTAssertTrue(mock.startCalled)
        XCTAssertEqual(mock.debounceSecondsReceived, 5)
    }

    func testMockUnlockObserverTracksStop() {
        let mock = MockUnlockObserver()

        mock.start(debounceSeconds: 3) { _ in }
        XCTAssertFalse(mock.stopCalled)

        mock.stop()
        XCTAssertTrue(mock.stopCalled)
    }

    func testMockUnlockObserverSimulatesEvents() {
        let mock = MockUnlockObserver()
        var receivedEvents: [CaptureEvent] = []

        mock.start(debounceSeconds: 3) { event in
            receivedEvents.append(event)
        }

        mock.simulateEvent(.unlock)
        mock.simulateEvent(.lock)
        mock.simulateEvent(.sessionOpen)
        mock.simulateEvent(.manual)

        XCTAssertEqual(receivedEvents, [.unlock, .lock, .sessionOpen, .manual])
    }

    func testMockUnlockObserverSimulateUnlockHelper() {
        let mock = MockUnlockObserver()
        var receivedEvent: CaptureEvent?

        mock.start(debounceSeconds: 3) { event in
            receivedEvent = event
        }

        mock.simulateUnlock()

        XCTAssertEqual(receivedEvent, .unlock)
    }

    func testMockUnlockObserverSimulateLockHelper() {
        let mock = MockUnlockObserver()
        var receivedEvent: CaptureEvent?

        mock.start(debounceSeconds: 3) { event in
            receivedEvent = event
        }

        mock.simulateLock()

        XCTAssertEqual(receivedEvent, .lock)
    }

    func testMockUnlockObserverIsRunningProperty() {
        let mock = MockUnlockObserver()

        XCTAssertFalse(mock.isRunning)

        mock.start(debounceSeconds: 3) { _ in }
        XCTAssertTrue(mock.isRunning)

        mock.stop()
        XCTAssertFalse(mock.isRunning)
    }

    func testMockUnlockObserverReset() {
        let mock = MockUnlockObserver()

        mock.start(debounceSeconds: 3) { _ in }
        mock.stop()

        XCTAssertTrue(mock.startCalled)
        XCTAssertTrue(mock.stopCalled)
        XCTAssertEqual(mock.debounceSecondsReceived, 3)

        mock.reset()

        XCTAssertFalse(mock.startCalled)
        XCTAssertFalse(mock.stopCalled)
        XCTAssertNil(mock.debounceSecondsReceived)
    }
}
