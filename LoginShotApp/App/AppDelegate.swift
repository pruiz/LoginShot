import AppKit

/// Main application delegate — lifecycle management, config loading, and capture orchestration.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var config: AppConfig = .default
    private var menuBarController: MenuBarController?
    private var unlockObserver: UnlockObserver?
    private let captureService: CaptureServiceProtocol = CaptureService()
    private let storageWriter: StorageWriterProtocol = StorageWriter()

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("LoginShot starting up")

        // 1. Load configuration
        reloadConfig()

        // 2. Setup menu bar if enabled
        if config.ui.menuBarIcon {
            setupMenuBar()
        } else {
            Log.app.info("Menu bar icon disabled by config; running headless")
        }

        // 3. Setup unlock observer
        let observer = UnlockObserver()
        if config.triggers.onUnlock {
            observer.start(debounceSeconds: config.capture.debounceSeconds) { [weak self] event in
                self?.handleCaptureEvent(event)
            }
        }
        self.unlockObserver = observer

        // 4. Fire session-open capture if enabled
        if config.triggers.onSessionOpen {
            handleCaptureEvent(.sessionOpen)
        }

        Log.app.info("LoginShot ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        unlockObserver?.stop()
        menuBarController?.teardown()
        Log.app.info("LoginShot shutting down")
    }

    // MARK: - Capture Pipeline

    /// Run the full capture pipeline for a given event.
    private func handleCaptureEvent(_ event: CaptureEvent) {
        Log.app.info("Capture event: \(event.rawValue)")

        Task { @MainActor [config, captureService, storageWriter] in
            do {
                // 1. Capture JPEG from camera
                let result = try await captureService.captureJPEG(
                    maxWidth: config.output.maxWidth,
                    quality: config.output.jpegQuality
                )

                // 2. Build metadata
                let filename = Self.makeFilename(event: event, format: config.output.format)
                let outputPath = (config.output.directory as NSString)
                    .appendingPathComponent(filename)
                let metadata = CaptureMetadata.build(
                    event: event,
                    outputPath: outputPath,
                    cameraInfo: result.cameraInfo
                )

                // 3. Write to disk
                try await storageWriter.writeCapture(
                    event: event,
                    jpegData: result.jpegData,
                    metadata: metadata,
                    config: config
                )

                Log.app.info("Capture complete: \(filename)")
            } catch {
                Log.app.error("Capture failed for event '\(event.rawValue)': \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Config

    private func reloadConfig() {
        let previousMenuBarEnabled = config.ui.menuBarIcon
        config = ConfigLoader.load()

        let currentMenuBarEnabled = self.config.ui.menuBarIcon
        if currentMenuBarEnabled != previousMenuBarEnabled {
            Log.config.warning("ui.menuBarIcon changed to \(currentMenuBarEnabled); restart required to apply")
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        let controller = MenuBarController(
            outputDirectory: config.output.directory,
            onCaptureNow: { [weak self] in
                self?.handleCaptureEvent(.manual)
            },
            onReloadConfig: { [weak self] in
                self?.reloadConfig()
            }
        )
        controller.setup()
        self.menuBarController = controller
    }

    // MARK: - Filename Generation

    /// Generate a timestamped filename: YYYY-MM-DDTHH-mm-ss-<event>.<ext>
    static func makeFilename(event: CaptureEvent, format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let timestamp = formatter.string(from: Date())
        return "\(timestamp)-\(event.rawValue).\(format)"
    }
}
