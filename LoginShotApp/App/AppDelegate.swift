import AppKit

/// Main application delegate — lifecycle management, config loading, and capture orchestration.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Dependencies

    private let captureService: CaptureServiceProtocol
    private let storageWriter: StorageWriterProtocol
    private let configLoader: ConfigLoaderProtocol
    private let unlockObserverFactory: @MainActor () -> UnlockObserving
    private let dateProvider: DateProviderProtocol

    // MARK: - State

    private var config: AppConfig = .default
    private var menuBarController: MenuBarController?
    private var unlockObserver: UnlockObserving?

    // MARK: - Initialization

    /// Production initializer with default dependencies.
    override init() {
        self.captureService = CaptureService()
        self.storageWriter = StorageWriter()
        self.configLoader = ConfigLoaderImpl()
        self.unlockObserverFactory = { UnlockObserver() }
        self.dateProvider = SystemDateProvider()
        super.init()
    }

    /// Test initializer with injectable dependencies.
    init(
        captureService: CaptureServiceProtocol,
        storageWriter: StorageWriterProtocol,
        configLoader: ConfigLoaderProtocol,
        unlockObserverFactory: @escaping @MainActor () -> UnlockObserving,
        dateProvider: DateProviderProtocol = SystemDateProvider()
    ) {
        self.captureService = captureService
        self.storageWriter = storageWriter
        self.configLoader = configLoader
        self.unlockObserverFactory = unlockObserverFactory
        self.dateProvider = dateProvider
        super.init()
    }

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
        let observer = unlockObserverFactory()
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
    func handleCaptureEvent(_ event: CaptureEvent) {
        Log.app.info("Capture event: \(event.rawValue)")

        Task { @MainActor [config, captureService, storageWriter, dateProvider] in
            do {
                // 1. Capture JPEG from camera
                let result = try await captureService.captureJPEG(
                    maxWidth: config.output.maxWidth,
                    quality: config.output.jpegQuality
                )

                // 2. Build metadata
                let filename = Self.makeFilename(
                    event: event,
                    format: config.output.format,
                    date: dateProvider.now()
                )
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

    func reloadConfig() {
        let previousMenuBarEnabled = config.ui.menuBarIcon
        config = configLoader.load()

        let currentMenuBarEnabled = self.config.ui.menuBarIcon
        if currentMenuBarEnabled != previousMenuBarEnabled {
            Log.config.warning("ui.menuBarIcon changed to \(currentMenuBarEnabled); restart required to apply")
        }
    }

    private func generateSampleConfig() {
        do {
            let path = try ConfigWriter.writeSampleConfig()
            Log.app.info("Sample config written to \(path)")

            // Reveal in Finder
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch ConfigWriterError.fileAlreadyExists(let path) {
            Log.app.warning("Config file already exists at \(path); not overwriting")
            // Still reveal the existing file
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            Log.app.error("Failed to generate sample config: \(error.localizedDescription)")
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        let controller = MenuBarController(
            outputDirectoryProvider: { [weak self] in
                self?.config.output.directory ?? AppConfig.default.output.directory
            },
            onCaptureNow: { [weak self] in
                self?.handleCaptureEvent(.manual)
            },
            onReloadConfig: { [weak self] in
                self?.reloadConfig()
            },
            onGenerateConfig: { [weak self] in
                self?.generateSampleConfig()
            }
        )
        controller.setup()
        self.menuBarController = controller
    }

    // MARK: - Filename Generation

    /// Generate a timestamped filename: YYYY-MM-DDTHH-mm-ss-<event>.<ext>
    /// - Parameters:
    ///   - event: The capture event type.
    ///   - format: The file extension (e.g., "jpg").
    ///   - date: The date to use for timestamp (defaults to current date).
    /// - Returns: Formatted filename string.
    static func makeFilename(event: CaptureEvent, format: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let timestamp = formatter.string(from: date)
        return "\(timestamp)-\(event.rawValue).\(format)"
    }

    // MARK: - Test Helpers

    /// Get the current config (for testing).
    var currentConfig: AppConfig {
        config
    }
}
