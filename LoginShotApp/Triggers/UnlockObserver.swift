import AppKit
import Foundation

// MARK: - UnlockObserving Protocol

/// Protocol for unlock observation (test seam).
@MainActor
protocol UnlockObserving: AnyObject {
    func start(debounceSeconds: Int, handler: @escaping @MainActor (CaptureEvent) -> Void)
    func stop()
}

// MARK: - UnlockObserver Implementation

/// Observes user session unlock/lock activity and fires a capture callback.
/// Uses layered notification sources for robustness across macOS versions:
///   - NSWorkspace.screensDidWakeNotification
///   - NSWorkspace.sessionDidBecomeActiveNotification
///   - NSWorkspace.sessionDidResignActiveNotification
///   - DistributedNotificationCenter "com.apple.screenIsUnlocked"
///   - DistributedNotificationCenter "com.apple.screenIsLocked"
///
/// Debounces repeated signals independently for unlock and lock events.
@MainActor
final class UnlockObserver: UnlockObserving {

    private static let sessionInactiveLockDelayNanos: UInt64 = 700_000_000

    private var handler: (@MainActor (CaptureEvent) -> Void)?
    private var isRunning = false
    private var unlockDebouncer: Debouncer?
    private var lockDebouncer: Debouncer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var pendingSessionInactiveLockTask: Task<Void, Never>?

    /// Start observing unlock/session-active events.
    /// - Parameters:
    ///   - debounceSeconds: Minimum interval between firings (suppresses duplicate OS signals).
    ///   - handler: Called on the main actor when an unlock event should trigger a capture.
    func start(debounceSeconds: Int, handler: @escaping @MainActor (CaptureEvent) -> Void) {
        guard !isRunning else {
            Log.triggers.warning("UnlockObserver.start() called but already running")
            return
        }
        self.handler = handler
        self.unlockDebouncer = Debouncer(seconds: debounceSeconds)
        self.lockDebouncer = Debouncer(seconds: debounceSeconds)
        self.isRunning = true

        let wsCenter = NSWorkspace.shared.notificationCenter

        // 1. Screen wake (covers lid-open, display wake from sleep)
        let screenWake = wsCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleSignal(event: .unlock, source: "screensDidWake")
            }
        }
        workspaceObservers.append(screenWake)

        // 2. Session became active (covers fast-user-switch back to this session)
        let sessionActive = wsCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.cancelPendingSessionInactiveLock(reason: "sessionDidBecomeActive")
                self?.handleSignal(event: .unlock, source: "sessionDidBecomeActive")
            }
        }
        workspaceObservers.append(sessionActive)

        // 3. Session resigned active (lock / fast user switch away)
        let sessionInactive = wsCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleSessionInactiveLockFallback()
            }
        }
        workspaceObservers.append(sessionInactive)

        // 4. Distributed notification for screen unlock (most direct signal)
        let distributed = DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.cancelPendingSessionInactiveLock(reason: "screenIsUnlocked")
                self?.handleSignal(event: .unlock, source: "screenIsUnlocked")
            }
        }
        distributedObservers.append(distributed)

        // 5. Distributed notification for screen lock (most direct signal)
        let distributedLock = DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.cancelPendingSessionInactiveLock(reason: "screenIsLocked")
                self?.handleSignal(event: .lock, source: "screenIsLocked")
            }
        }
        distributedObservers.append(distributedLock)

        Log.triggers.info("UnlockObserver started (debounce: \(debounceSeconds)s, 5 signal sources)")
    }

    /// Stop observing and release all resources.
    func stop() {
        guard isRunning else { return }

        let wsCenter = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            wsCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        let distributedCenter = DistributedNotificationCenter.default()
        for observer in distributedObservers {
            distributedCenter.removeObserver(observer)
        }
        distributedObservers.removeAll()

        pendingSessionInactiveLockTask?.cancel()
        pendingSessionInactiveLockTask = nil

        handler = nil
        unlockDebouncer = nil
        lockDebouncer = nil
        isRunning = false
        Log.triggers.info("UnlockObserver stopped")
    }

    // MARK: - Private

    private func scheduleSessionInactiveLockFallback() {
        cancelPendingSessionInactiveLock(reason: "rescheduled")
        pendingSessionInactiveLockTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.sessionInactiveLockDelayNanos)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.pendingSessionInactiveLockTask = nil
                self?.handleSignal(event: .lock, source: "sessionDidResignActive(fallback)")
            }
        }
        Log.triggers.debug("Scheduled fallback lock capture from sessionDidResignActive")
    }

    private func cancelPendingSessionInactiveLock(reason: String) {
        guard pendingSessionInactiveLockTask != nil else { return }
        pendingSessionInactiveLockTask?.cancel()
        pendingSessionInactiveLockTask = nil
        Log.triggers.debug("Cancelled pending fallback lock capture (reason: \(reason))")
    }

    private func handleSignal(event: CaptureEvent, source: String) {
        Log.triggers.debug("\(event.rawValue) signal received: \(source)")

        guard let handler = handler else { return }

        let debouncer: Debouncer?
        switch event {
        case .unlock:
            debouncer = unlockDebouncer
        case .lock:
            debouncer = lockDebouncer
        default:
            debouncer = nil
        }
        guard let debouncer else { return }

        Task { @MainActor in
            let shouldFire = await debouncer.shouldFire()
            if shouldFire {
                Log.triggers.info("Firing \(event.rawValue) capture (source: \(source))")
                handler(event)
            } else {
                Log.triggers.debug("\(event.rawValue) signal debounced (source: \(source))")
            }
        }
    }
}
