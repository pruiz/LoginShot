import Foundation

/// Writes a sample configuration file with default values and comments.
enum ConfigWriter {

    /// Default path for the generated config file.
    static var defaultPath: String {
        ("~/Library/Application Support/LoginShot/config.yml" as NSString).expandingTildeInPath
    }

    /// Generate a sample config.yml with defaults and explanatory comments.
    /// - Parameter path: File path to write to. Parent directory is created if missing.
    /// - Returns: The absolute path of the written file.
    @discardableResult
    static func writeSampleConfig(to path: String? = nil) throws -> String {
        let target = path ?? defaultPath
        let dir = (target as NSString).deletingLastPathComponent

        // Ensure directory exists
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        // Don't overwrite existing config
        if fm.fileExists(atPath: target) {
            Log.config.warning("Config file already exists at \(target); not overwriting")
            throw ConfigWriterError.fileAlreadyExists(target)
        }

        let content = sampleYAML()
        try content.write(toFile: target, atomically: true, encoding: .utf8)
        Log.config.info("Wrote sample config to \(target)")

        return target
    }

    /// Persist config values to YAML, overwriting existing file atomically.
    @discardableResult
    static func writeConfig(_ config: AppConfig, to path: String) throws -> String {
        let dir = (path as NSString).deletingLastPathComponent
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        let yaml = serialize(config: config)
        let tempPath = path + ".tmp-\(UUID().uuidString)"
        try yaml.write(toFile: tempPath, atomically: true, encoding: .utf8)
        if fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
        }
        try fm.moveItem(atPath: tempPath, toPath: path)
        Log.config.info("Wrote config to \(path)")
        return path
    }

    /// The sample YAML content with comments.
    static func sampleYAML() -> String {
        """
        # LoginShot configuration
        # Documentation: https://github.com/pruiz/LoginShot#configuration-yaml

        output:
          # Where to save captured images. Supports ~ for home directory.
          directory: "~/Pictures/LoginShot"

          # Image format. Only "jpg" is supported in v1.
          format: "jpg"

          # Maximum image width in pixels. 0 = keep original size.
          maxWidth: 1280

          # JPEG compression quality (0.0 = minimum, 1.0 = maximum).
          jpegQuality: 0.85

        triggers:
          # Capture when the app starts after user login.
          onSessionOpen: true

          # Capture when the user session is unlocked.
          onUnlock: true

          # Best-effort capture when the user session is locked.
          # macOS emits multiple lock-related signals; debounce suppresses duplicates.
          onLock: true

        metadata:
          # Write a JSON sidecar file next to each image.
          writeSidecar: true

        ui:
          # Show a menu bar icon. Set to false for fully headless operation.
          menuBarIcon: true

        capture:
          # Suppress simulated shutter sound (reserved for future use).
          silent: true

          # Minimum seconds between captures from unlock signals.
          # Prevents duplicate captures from multiple OS notifications.
          debounceSeconds: 3

          # Camera unique identifier. null = automatic/default camera.
          cameraUniqueID: null

        logging:
          # Write app logs to files in addition to macOS unified logging.
          # Default false keeps logging fully OS-managed.
          enableFileLogging: false

          # Directory for daily LoginShot logs.
          directory: "~/Library/Logs/LoginShot"

          # Keep log files newer than this number of days.
          retentionDays: 14

          # Run cleanup this often.
          cleanupIntervalHours: 24

          # Trace|Debug|Information|Warning|Error|Critical|None
          level: "Information"
        """
    }

    private static func serialize(config: AppConfig) -> String {
        let cameraUniqueID: String
        if let configuredID = config.capture.cameraUniqueID {
            let escaped = configuredID.replacingOccurrences(of: "\"", with: "\\\"")
            cameraUniqueID = "\"\(escaped)\""
        } else {
            cameraUniqueID = "null"
        }

        return """
        output:
          directory: "\(config.output.directory)"
          format: "\(config.output.format)"
          maxWidth: \(config.output.maxWidth)
          jpegQuality: \(String(format: "%.2f", config.output.jpegQuality))

        triggers:
          onSessionOpen: \(config.triggers.onSessionOpen)
          onUnlock: \(config.triggers.onUnlock)
          onLock: \(config.triggers.onLock)

        metadata:
          writeSidecar: \(config.metadata.writeSidecar)

        ui:
          menuBarIcon: \(config.ui.menuBarIcon)

        capture:
          silent: \(config.capture.silent)
          debounceSeconds: \(config.capture.debounceSeconds)
          cameraUniqueID: \(cameraUniqueID)

        logging:
          enableFileLogging: \(config.logging.enableFileLogging)
          directory: "\(config.logging.directory)"
          retentionDays: \(config.logging.retentionDays)
          cleanupIntervalHours: \(config.logging.cleanupIntervalHours)
          level: "\(config.logging.level)"
        """
    }
}

/// Errors from the config writer.
enum ConfigWriterError: Error, Sendable {
    case fileAlreadyExists(String)
}
