@testable import LoginShot
import Foundation

/// Mock implementation of UnlockObserving for testing unlock event handling.
@MainActor
final class MockUnlockObserver: UnlockObserving {

    /// Whether start() has been called.
    var startCalled = false

    /// Whether stop() has been called.
    var stopCalled = false

    /// The debounceSeconds value received in start().
    var debounceSecondsReceived: Int?

    /// The captured handler from start().
    private var capturedHandler: (@MainActor (CaptureEvent) -> Void)?

    /// Whether the observer is currently "running".
    var isRunning: Bool {
        startCalled && !stopCalled
    }

    func start(debounceSeconds: Int, handler: @escaping @MainActor (CaptureEvent) -> Void) {
        startCalled = true
        stopCalled = false
        debounceSecondsReceived = debounceSeconds
        capturedHandler = handler
    }

    func stop() {
        stopCalled = true
        capturedHandler = nil
    }

    // MARK: - Test Helpers

    /// Simulate an unlock event being received.
    func simulateEvent(_ event: CaptureEvent) {
        capturedHandler?(event)
    }

    /// Simulate an unlock event.
    func simulateUnlock() {
        simulateEvent(.unlock)
    }

    /// Reset all recorded state.
    func reset() {
        startCalled = false
        stopCalled = false
        debounceSecondsReceived = nil
        capturedHandler = nil
    }
}
