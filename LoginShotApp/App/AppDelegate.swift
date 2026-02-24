import AppKit

protocol AlertPresenting: Sendable {
    @MainActor func showInfo(title: String, message: String)
    @MainActor func showError(title: String, message: String)
}

struct NSAlertPresenter: AlertPresenting {
    @MainActor
    func showInfo(title: String, message: String) {
        show(title: title, message: message, style: .informational)
    }

    @MainActor
    func showError(title: String, message: String) {
        show(title: title, message: message, style: .warning)
    }

    @MainActor
    private func show(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

protocol ConfigReloadCoordinating: AnyObject {
    func bind(configPath: String?)
    func unbind()
}

final class ConfigReloadCoordinator: ConfigReloadCoordinating, @unchecked Sendable {
    private let onReloadRequested: @MainActor () -> Void
    private let debounceInterval: TimeInterval
    private let queue = DispatchQueue(label: "dev.pruiz.LoginShot.config-watcher")

    private var watchedPath: String?
    private var directoryFD: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var pendingWorkItem: DispatchWorkItem?

    init(
        debounceInterval: TimeInterval = 1.2,
        onReloadRequested: @escaping @MainActor () -> Void
    ) {
        self.debounceInterval = debounceInterval
        self.onReloadRequested = onReloadRequested
    }

    deinit {
        unbind()
    }

    func bind(configPath: String?) {
        queue.async { [weak self] in
            guard let self else { return }

            guard let configPath else {
                self.stopWatchingLocked()
                return
            }

            if self.watchedPath == configPath, self.source != nil {
                return
            }

            self.stopWatchingLocked()
            self.watchedPath = configPath

            let directory = (configPath as NSString).deletingLastPathComponent
            let fd = open(directory, O_EVTONLY)
            guard fd >= 0 else {
                Log.config.warning("Could not watch config directory: \(directory)")
                return
            }

            self.directoryFD = fd
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete, .extend, .attrib],
                queue: self.queue
            )

            source.setEventHandler { [weak self] in
                self?.scheduleDebouncedReloadLocked()
            }

            source.setCancelHandler { [weak self] in
                guard let self else { return }
                if self.directoryFD >= 0 {
                    close(self.directoryFD)
                    self.directoryFD = -1
                }
            }

            self.source = source
            source.resume()
            Log.config.info("Watching config changes at \(configPath)")
        }
    }

    func unbind() {
        queue.async { [weak self] in
            self?.stopWatchingLocked()
        }
    }

    private func stopWatchingLocked() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        watchedPath = nil

        source?.cancel()
        source = nil

        if directoryFD >= 0 {
            close(directoryFD)
            directoryFD = -1
        }
    }

    private func scheduleDebouncedReloadLocked() {
        pendingWorkItem?.cancel()
        let reloadCallback = onReloadRequested

        let workItem = DispatchWorkItem {
            DispatchQueue.main.async {
                reloadCallback()
            }
        }

        pendingWorkItem = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
}

/// Main application delegate — lifecycle management, config loading, and capture orchestration.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private enum ReloadTrigger: Equatable {
        case startup
        case manual
        case auto
    }

    // MARK: - Dependencies

    private let captureService: CaptureServiceProtocol
    private let storageWriter: StorageWriterProtocol
    private let configLoader: ConfigLoaderProtocol
    private let unlockObserver: UnlockObserving
    private let dateProvider: DateProviderProtocol
    private let alertPresenter: AlertPresenting

    // MARK: - State

    private var config: AppConfig = .default
    private var configSourcePath: String?
    private var menuBarController: MenuBarController?
    private var configReloadCoordinator: ConfigReloadCoordinating?

    // MARK: - Initialization

    /// Production initializer with default dependencies.
    override init() {
        self.captureService = CaptureService()
        self.storageWriter = StorageWriter()
        self.configLoader = ConfigLoaderImpl()
        self.unlockObserver = UnlockObserver()
        self.dateProvider = SystemDateProvider()
        self.alertPresenter = NSAlertPresenter()
        super.init()
    }

    /// Test initializer with injectable dependencies.
    init(
        captureService: CaptureServiceProtocol,
        storageWriter: StorageWriterProtocol,
        configLoader: ConfigLoaderProtocol,
        unlockObserver: UnlockObserving,
        dateProvider: DateProviderProtocol = SystemDateProvider(),
        alertPresenter: AlertPresenting = NSAlertPresenter()
    ) {
        self.captureService = captureService
        self.storageWriter = storageWriter
        self.configLoader = configLoader
        self.unlockObserver = unlockObserver
        self.dateProvider = dateProvider
        self.alertPresenter = alertPresenter
        super.init()
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("LoginShot starting up")

        // 1. Load configuration
        reloadConfig(trigger: .startup)

        let reloadCoordinator = ConfigReloadCoordinator { [weak self] in
            self?.reloadConfig(trigger: .auto)
        }
        reloadCoordinator.bind(configPath: configSourcePath)
        configReloadCoordinator = reloadCoordinator

        // 2. Setup menu bar if enabled
        if config.ui.menuBarIcon {
            setupMenuBar()
        } else {
            Log.app.info("Menu bar icon disabled by config; running headless")
        }

        // 3. Setup unlock observer
        if config.triggers.onUnlock || config.triggers.onLock {
            unlockObserver.start(debounceSeconds: config.capture.debounceSeconds) { [weak self] event in
                guard let self else { return }

                switch event {
                case .unlock where self.config.triggers.onUnlock:
                    self.handleCaptureEvent(event)
                case .lock where self.config.triggers.onLock:
                    self.handleCaptureEvent(event)
                default:
                    Log.triggers.debug("Ignoring \(event.rawValue) event (disabled by config)")
                }
            }
        }

        // 4. Fire session-open capture if enabled
        if config.triggers.onSessionOpen {
            handleCaptureEvent(.sessionOpen)
        }

        Log.app.info("LoginShot ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        configReloadCoordinator?.unbind()
        unlockObserver.stop()
        menuBarController?.teardown()
        Log.app.info("LoginShot shutting down")
    }

    // MARK: - Capture Pipeline

    /// Run the full capture pipeline for a given event.
    func handleCaptureEvent(_ event: CaptureEvent) {
        Log.app.info("Capture event: \(event.rawValue)")

        Task { @MainActor [config, captureService, storageWriter, dateProvider] in
            let startedAt = Date()
            let filename = Self.makeFilename(
                event: event,
                format: config.output.format,
                date: dateProvider.now()
            )
            let outputPath = (config.output.directory as NSString)
                .appendingPathComponent(filename)

            do {
                // 1. Capture JPEG from camera
                let result = try await captureService.captureJPEG(
                    maxWidth: config.output.maxWidth,
                    quality: config.output.jpegQuality,
                    cameraUniqueID: config.capture.cameraUniqueID
                )

                // 2. Build metadata
                let metadata = CaptureMetadata.build(
                    event: event,
                    outputPath: outputPath,
                    cameraInfo: result.cameraInfo,
                    success: true,
                    diagnostics: CaptureMetadata.Diagnostics(
                        backend: "avfoundation",
                        durationMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                        attemptCount: 1,
                        failureCode: nil
                    )
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

                let metadata = CaptureMetadata.build(
                    event: event,
                    outputPath: outputPath,
                    cameraInfo: .unknown,
                    success: false,
                    failure: CaptureMetadata.FailureInfo(
                        reason: "camera_capture_failed",
                        message: error.localizedDescription
                    ),
                    diagnostics: CaptureMetadata.Diagnostics(
                        backend: "avfoundation",
                        durationMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                        attemptCount: 1,
                        failureCode: "exception"
                    )
                )

                do {
                    try await storageWriter.writeCapture(
                        event: event,
                        jpegData: nil,
                        metadata: metadata,
                        config: config
                    )
                } catch {
                    Log.app.error("Failed to persist failure sidecar for event '\(event.rawValue)': \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Config

    func reloadConfig() {
        reloadConfig(trigger: .manual)
    }

    private func reloadConfig(trigger: ReloadTrigger) {
        let previousMenuBarEnabled = config.ui.menuBarIcon

        let loadResult = configLoader.loadResult()
        switch loadResult {
        case .loaded(let loadedConfig, let sourcePath):
            config = loadedConfig
            configSourcePath = sourcePath
            Log.config.info("Config loaded from \(sourcePath)")
        case .notFound(let defaults):
            if trigger == .auto, configSourcePath != nil {
                Log.config.warning("Config file temporarily unavailable during auto-reload; keeping previous configuration")
                return
            }
            config = defaults
            configSourcePath = nil
            Log.config.info("No config file found; using defaults")
        case .failed(let path, let error):
            Log.config.error("Config reload failed for \(path): \(error.localizedDescription). Keeping previous valid configuration")
            if trigger == .manual {
                alertPresenter.showError(
                    title: "LoginShot",
                    message: "Config reload failed:\n\(error.localizedDescription)\n\nKeeping previous valid configuration."
                )
            }
            return
        }

        Log.configureFileLogging(
            enabled: config.logging.enableFileLogging,
            directory: config.logging.directory,
            retentionDays: config.logging.retentionDays,
            cleanupIntervalHours: config.logging.cleanupIntervalHours,
            level: config.logging.level
        )

        let currentMenuBarEnabled = self.config.ui.menuBarIcon
        if currentMenuBarEnabled != previousMenuBarEnabled {
            Log.config.warning("ui.menuBarIcon changed to \(currentMenuBarEnabled); restart required to apply")
        }

        configReloadCoordinator?.bind(configPath: configSourcePath)

        if trigger == .manual {
            alertPresenter.showInfo(title: "LoginShot", message: "Configuration reloaded successfully.")
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
            onEditConfig: { [weak self] in
                self?.editConfig()
            },
            onGenerateConfig: { [weak self] in
                self?.generateSampleConfig()
            },
            onOpenLog: { [weak self] in
                self?.openCurrentLogFile()
            },
            cameraMenuStateProvider: { [weak self] in
                self?.cameraMenuState() ?? MenuBarController.CameraMenuState(selectedUniqueID: nil, devices: [])
            },
            onSelectCamera: { [weak self] uniqueID in
                self?.selectCamera(uniqueID: uniqueID)
            },
            onVerifyCamera: { [weak self] in
                self?.verifySelectedCamera()
            }
        )
        controller.setup()
        self.menuBarController = controller
    }

    private func openCurrentLogFile() {
        Task { @MainActor in
            guard let path = await FileLogger.shared.currentLogPath() else {
                Log.ui.info("Open Log requested, but file logging is disabled")
                return
            }

            let url = URL(fileURLWithPath: path)
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            NSWorkspace.shared.open(url)
        }
    }

    private func editConfig() {
        let path: String
        if let existingPath = configSourcePath {
            path = existingPath
        } else {
            do {
                path = try ConfigWriter.writeSampleConfig()
                configSourcePath = path
                configReloadCoordinator?.bind(configPath: path)
                Log.config.info("Created sample config for editing at \(path)")
            } catch ConfigWriterError.fileAlreadyExists(let existingPath) {
                path = existingPath
                configSourcePath = existingPath
                configReloadCoordinator?.bind(configPath: existingPath)
            } catch {
                Log.config.error("Failed to prepare config file for editing: \(error.localizedDescription)")
                alertPresenter.showError(title: "LoginShot", message: "Failed to open config file:\n\(error.localizedDescription)")
                return
            }
        }

        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }

    private func cameraMenuState() -> MenuBarController.CameraMenuState {
        let devices = captureService.listCameras().sorted {
            $0.deviceName.localizedCaseInsensitiveCompare($1.deviceName) == .orderedAscending
        }

        return MenuBarController.CameraMenuState(
            selectedUniqueID: config.capture.cameraUniqueID,
            devices: devices
        )
    }

    private func selectCamera(uniqueID: String?) {
        let previousID = config.capture.cameraUniqueID
        config.capture.cameraUniqueID = uniqueID

        do {
            try persistCurrentConfig()
            let label = uniqueID ?? "auto"
            Log.config.info("Updated camera selection to \(label)")
        } catch {
            config.capture.cameraUniqueID = previousID
            Log.config.error("Failed to persist camera selection: \(error.localizedDescription)")
            alertPresenter.showError(
                title: "LoginShot",
                message: "Failed to save camera selection:\n\(error.localizedDescription)"
            )
        }
    }

    private func verifySelectedCamera() {
        let selectedID = config.capture.cameraUniqueID
        Task { @MainActor [captureService, config, alertPresenter] in
            do {
                _ = try await captureService.captureJPEG(
                    maxWidth: config.output.maxWidth,
                    quality: config.output.jpegQuality,
                    cameraUniqueID: selectedID
                )
                alertPresenter.showInfo(title: "LoginShot", message: "Camera verification succeeded.")
            } catch {
                alertPresenter.showError(
                    title: "LoginShot",
                    message: "Camera verification failed:\n\(error.localizedDescription)"
                )
            }
        }
    }

    private func persistCurrentConfig() throws {
        if configSourcePath == nil {
            configSourcePath = try ConfigWriter.writeSampleConfig()
        }

        guard let configSourcePath else {
            throw NSError(
                domain: "LoginShot.Config",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing config source path"]
            )
        }

        _ = try ConfigWriter.writeConfig(config, to: configSourcePath)
        configReloadCoordinator?.bind(configPath: configSourcePath)
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
