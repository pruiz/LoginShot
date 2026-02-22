import AppKit
import Foundation

/// Observes user session unlock / screen-wake events and fires a capture callback.
/// Uses layered notification sources for robustness across macOS versions:
///   - NSWorkspace.screensDidWakeNotification
///   - NSWorkspace.sessionDidBecomeActiveNotification
///   - DistributedNotificationCenter "com.apple.screenIsUnlocked"
///
/// Debounces repeated signals so only one capture fires per unlock cycle.
@MainActor
final class UnlockObserver {

    private var handler: (@MainActor (CaptureEvent) -> Void)?
    private var isRunning = false
    private var debouncer: Debouncer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObserver: NSObjectProtocol?

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
        self.debouncer = Debouncer(seconds: debounceSeconds)
        self.isRunning = true

        let wsCenter = NSWorkspace.shared.notificationCenter

        // 1. Screen wake (covers lid-open, display wake from sleep)
        let screenWake = wsCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleSignal(source: "screensDidWake")
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
                self?.handleSignal(source: "sessionDidBecomeActive")
            }
        }
        workspaceObservers.append(sessionActive)

        // 3. Distributed notification for screen unlock (most direct signal)
        let distributed = DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleSignal(source: "screenIsUnlocked")
            }
        }
        distributedObserver = distributed

        Log.triggers.info("UnlockObserver started (debounce: \(debounceSeconds)s, 3 signal sources)")
    }

    /// Stop observing and release all resources.
    func stop() {
        guard isRunning else { return }

        let wsCenter = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            wsCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        if let distributed = distributedObserver {
            DistributedNotificationCenter.default().removeObserver(distributed)
            distributedObserver = nil
        }

        handler = nil
        debouncer = nil
        isRunning = false
        Log.triggers.info("UnlockObserver stopped")
    }

    // MARK: - Private

    private func handleSignal(source: String) {
        Log.triggers.debug("Unlock signal received: \(source)")

        guard let handler = handler, let debouncer = debouncer else { return }

        Task { @MainActor in
            let shouldFire = await debouncer.shouldFire()
            if shouldFire {
                Log.triggers.info("Firing unlock capture (source: \(source))")
                handler(.unlock)
            } else {
                Log.triggers.debug("Unlock signal debounced (source: \(source))")
            }
        }
    }
}
