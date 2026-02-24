import Foundation

/// Application configuration loaded from YAML.
/// All properties have safe defaults so the app runs even without a config file.
struct AppConfig: Sendable {
    var output: OutputConfig
    var triggers: TriggersConfig
    var metadata: MetadataConfig
    var ui: UIConfig
    var capture: CaptureConfig
    var logging: LoggingConfig

    struct OutputConfig: Sendable {
        var directory: String
        var format: String
        var maxWidth: Int
        var jpegQuality: Double

        static let `default` = OutputConfig(
            directory: ("~/Pictures/LoginShot" as NSString).expandingTildeInPath,
            format: "jpg",
            maxWidth: 1280,
            jpegQuality: 0.85
        )
    }

    struct TriggersConfig: Sendable {
        var onSessionOpen: Bool
        var onUnlock: Bool
        var onLock: Bool

        static let `default` = TriggersConfig(
            onSessionOpen: true,
            onUnlock: true,
            onLock: true
        )
    }

    struct MetadataConfig: Sendable {
        var writeSidecar: Bool

        static let `default` = MetadataConfig(writeSidecar: true)
    }

    struct UIConfig: Sendable {
        var menuBarIcon: Bool

        static let `default` = UIConfig(menuBarIcon: true)
    }

    struct CaptureConfig: Sendable {
        /// Reserved for future use. macOS does not play a shutter sound for
        /// AVFoundation still captures, so this has no effect in v1.
        var silent: Bool
        var debounceSeconds: Int
        var cameraUniqueID: String?

        static let `default` = CaptureConfig(silent: true, debounceSeconds: 3, cameraUniqueID: nil)
    }

    struct LoggingConfig: Sendable {
        var enableFileLogging: Bool
        var directory: String
        var retentionDays: Int
        var cleanupIntervalHours: Int
        var level: String

        static let `default` = LoggingConfig(
            enableFileLogging: false,
            directory: ("~/Library/Logs/LoginShot" as NSString).expandingTildeInPath,
            retentionDays: 14,
            cleanupIntervalHours: 24,
            level: "Information"
        )
    }

    static let `default` = AppConfig(
        output: .default,
        triggers: .default,
        metadata: .default,
        ui: .default,
        capture: .default,
        logging: .default
    )

    /// Validate and clamp config values to acceptable ranges.
    /// Returns a corrected copy and logs warnings for any adjustments.
    func validated() -> AppConfig {
        var config = self

        // output.format must be "jpg" in v1
        if config.output.format != "jpg" {
            Log.config.warning("output.format '\(config.output.format)' is not supported in v1; falling back to 'jpg'")
            config.output.format = "jpg"
        }

        // jpegQuality clamped to 0.0...1.0
        if config.output.jpegQuality < 0.0 || config.output.jpegQuality > 1.0 {
            let clamped = min(max(config.output.jpegQuality, 0.0), 1.0)
            Log.config.warning("output.jpegQuality \(config.output.jpegQuality) out of range; clamped to \(clamped)")
            config.output.jpegQuality = clamped
        }

        // maxWidth >= 0
        if config.output.maxWidth < 0 {
            Log.config.warning("output.maxWidth \(config.output.maxWidth) is negative; setting to 0 (no resize)")
            config.output.maxWidth = 0
        }

        // debounceSeconds >= 0
        if config.capture.debounceSeconds < 0 {
            Log.config.warning("capture.debounceSeconds \(config.capture.debounceSeconds) is negative; setting to 0")
            config.capture.debounceSeconds = 0
        }

        if let cameraUniqueID = config.capture.cameraUniqueID {
            let trimmed = cameraUniqueID.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                Log.config.warning("capture.cameraUniqueID is empty; using automatic camera selection")
                config.capture.cameraUniqueID = nil
            } else if trimmed != cameraUniqueID {
                config.capture.cameraUniqueID = trimmed
            }
        }

        if config.logging.retentionDays < 1 {
            Log.config.warning("logging.retentionDays \(config.logging.retentionDays) is invalid; setting to 14")
            config.logging.retentionDays = 14
        }

        if config.logging.cleanupIntervalHours < 1 {
            Log.config.warning("logging.cleanupIntervalHours \(config.logging.cleanupIntervalHours) is invalid; setting to 24")
            config.logging.cleanupIntervalHours = 24
        }

        if config.logging.level.isEmpty {
            Log.config.warning("logging.level is empty; setting to Information")
            config.logging.level = "Information"
        }

        return config
    }
}
