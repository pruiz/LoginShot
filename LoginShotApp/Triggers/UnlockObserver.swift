import Foundation

/// Observes user session unlock / screen-wake events and fires a callback.
/// Stub implementation — real observers will be wired in a future commit.
@MainActor
final class UnlockObserver {

    private var handler: ((CaptureEvent) -> Void)?
    private var isRunning = false

    /// Start observing unlock/session-active events.
    /// - Parameter handler: Called on the main actor when an unlock event is detected.
    func start(handler: @escaping (CaptureEvent) -> Void) {
        guard !isRunning else {
            Log.triggers.warning("UnlockObserver.start() called but already running")
            return
        }
        self.handler = handler
        self.isRunning = true

        // TODO: Subscribe to NSWorkspace session notifications and
        // DistributedNotificationCenter for screen unlock signals.
        // Will include debounce logic based on config.capture.debounceSeconds.
        Log.triggers.info("UnlockObserver started (stub — no real observers registered yet)")
    }

    /// Stop observing and release resources.
    func stop() {
        guard isRunning else { return }
        // TODO: Remove notification observers
        handler = nil
        isRunning = false
        Log.triggers.info("UnlockObserver stopped")
    }
}
