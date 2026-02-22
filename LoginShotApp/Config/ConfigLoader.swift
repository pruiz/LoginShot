import Foundation
import Yams

/// Loads and parses the YAML configuration file.
enum ConfigLoader {

    /// Ordered list of paths to search for config.yml (first found wins).
    private static let searchPaths: [String] = [
        ("~/.config/LoginShot/config.yml" as NSString).expandingTildeInPath,
        ("~/Library/Application Support/LoginShot/config.yml" as NSString).expandingTildeInPath
    ]

    /// Directory under Application Support to ensure exists.
    private static var appSupportDirectory: String {
        ("~/Library/Application Support/LoginShot" as NSString).expandingTildeInPath
    }

    /// Load configuration from disk, returning defaults if no file is found.
    static func load() -> AppConfig {
        ensureAppSupportDirectory()

        guard let path = firstExistingPath() else {
            Log.config.info("No config file found; using defaults")
            return AppConfig.default
        }

        Log.config.info("Loading config from \(path)")

        do {
            let contents = try String(contentsOfFile: path, encoding: .utf8)
            let config = try parse(yaml: contents)
            let validated = config.validated()
            Log.config.info("Config loaded and validated successfully")
            return validated
        } catch {
            Log.config.error("Failed to load config from \(path): \(error.localizedDescription); using defaults")
            return AppConfig.default
        }
    }

    // MARK: - Private

    private static func firstExistingPath() -> String? {
        for path in searchPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    private static func ensureAppSupportDirectory() {
        let fm = FileManager.default
        let dir = appSupportDirectory
        if !fm.fileExists(atPath: dir) {
            do {
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
                Log.config.info("Created config directory: \(dir)")
            } catch {
                Log.config.warning("Could not create config directory \(dir): \(error.localizedDescription)")
            }
        }
    }

    /// Parse YAML string into AppConfig, using defaults for missing keys.
    private static func parse(yaml: String) throws -> AppConfig {
        guard let root = try Yams.load(yaml: yaml) as? [String: Any] else {
            Log.config.warning("Config YAML is not a dictionary; using defaults")
            return AppConfig.default
        }

        let outputDict = root["output"] as? [String: Any] ?? [:]
        let triggersDict = root["triggers"] as? [String: Any] ?? [:]
        let metadataDict = root["metadata"] as? [String: Any] ?? [:]
        let uiDict = root["ui"] as? [String: Any] ?? [:]
        let captureDict = root["capture"] as? [String: Any] ?? [:]

        let output = AppConfig.OutputConfig(
            directory: expandPath(outputDict["directory"] as? String ?? "~/Pictures/LoginShot"),
            format: outputDict["format"] as? String ?? "jpg",
            maxWidth: outputDict["maxWidth"] as? Int ?? 1280,
            jpegQuality: outputDict["jpegQuality"] as? Double ?? 0.85
        )

        let triggers = AppConfig.TriggersConfig(
            onSessionOpen: triggersDict["onSessionOpen"] as? Bool ?? true,
            onUnlock: triggersDict["onUnlock"] as? Bool ?? true
        )

        let metadata = AppConfig.MetadataConfig(
            writeSidecar: metadataDict["writeSidecar"] as? Bool ?? true
        )

        let ui = AppConfig.UIConfig(
            menuBarIcon: uiDict["menuBarIcon"] as? Bool ?? true
        )

        let capture = AppConfig.CaptureConfig(
            silent: captureDict["silent"] as? Bool ?? true,
            debounceSeconds: captureDict["debounceSeconds"] as? Int ?? 3
        )

        return AppConfig(
            output: output,
            triggers: triggers,
            metadata: metadata,
            ui: ui,
            capture: capture
        )
    }

    /// Expand "~" prefix to the user's home directory.
    private static func expandPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
