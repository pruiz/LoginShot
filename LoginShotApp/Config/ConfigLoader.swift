import Foundation
import Yams

// MARK: - ConfigLoader Protocol

/// Protocol for loading configuration (test seam).
protocol ConfigLoaderProtocol: Sendable {
    func load() -> AppConfig
    func loadResult() -> ConfigLoadResult
}

/// Default implementation that wraps the static ConfigLoader methods.
struct ConfigLoaderImpl: ConfigLoaderProtocol, Sendable {
    func load() -> AppConfig {
        ConfigLoader.load()
    }

    func loadResult() -> ConfigLoadResult {
        ConfigLoader.loadResult()
    }
}

enum ConfigLoadResult {
    case loaded(config: AppConfig, sourcePath: String)
    case notFound(defaults: AppConfig)
    case failed(path: String, error: Error)
}

// MARK: - ConfigLoader Implementation

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
        switch loadResult() {
        case .loaded(let config, _):
            return config
        case .notFound(let defaults):
            return defaults
        case .failed(_, _):
            return AppConfig.default
        }
    }

    static func loadResult() -> ConfigLoadResult {
        ensureAppSupportDirectory()

        guard let path = firstExistingPath() else {
            Log.config.info("No config file found; using defaults")
            return .notFound(defaults: AppConfig.default)
        }

        Log.config.info("Loading config from \(path)")

        do {
            let contents = try String(contentsOfFile: path, encoding: .utf8)
            let config = try parse(yaml: contents)
            let validated = config.validated()
            Log.config.info("Config loaded and validated successfully")
            return .loaded(config: validated, sourcePath: path)
        } catch {
            Log.config.error("Failed to load config from \(path): \(error.localizedDescription)")
            return .failed(path: path, error: error)
        }
    }

    // MARK: - Internal (for testing)

    /// Parse YAML string into AppConfig, using defaults for missing keys.
    /// Internal access for unit testing via @testable import.
    static func parse(yaml: String) throws -> AppConfig {
        guard let root = try Yams.load(yaml: yaml) as? [String: Any] else {
            Log.config.warning("Config YAML is not a dictionary; using defaults")
            return AppConfig.default
        }

        let outputDict = root["output"] as? [String: Any] ?? [:]
        let triggersDict = root["triggers"] as? [String: Any] ?? [:]
        let metadataDict = root["metadata"] as? [String: Any] ?? [:]
        let uiDict = root["ui"] as? [String: Any] ?? [:]
        let captureDict = root["capture"] as? [String: Any] ?? [:]
        let loggingDict = root["logging"] as? [String: Any] ?? [:]

        let output = AppConfig.OutputConfig(
            directory: expandPath(outputDict["directory"] as? String ?? "~/Pictures/LoginShot"),
            format: outputDict["format"] as? String ?? "jpg",
            maxWidth: extractInt(outputDict["maxWidth"], default: 1280),
            jpegQuality: extractDouble(outputDict["jpegQuality"], default: 0.85)
        )

        let triggers = AppConfig.TriggersConfig(
            onSessionOpen: triggersDict["onSessionOpen"] as? Bool ?? true,
            onUnlock: triggersDict["onUnlock"] as? Bool ?? true,
            onLock: triggersDict["onLock"] as? Bool ?? true
        )

        let metadata = AppConfig.MetadataConfig(
            writeSidecar: metadataDict["writeSidecar"] as? Bool ?? true
        )

        let ui = AppConfig.UIConfig(
            menuBarIcon: uiDict["menuBarIcon"] as? Bool ?? true
        )

        let capture = AppConfig.CaptureConfig(
            silent: captureDict["silent"] as? Bool ?? true,
            debounceSeconds: extractInt(captureDict["debounceSeconds"], default: 3)
        )

        let logging = AppConfig.LoggingConfig(
            enableFileLogging: loggingDict["enableFileLogging"] as? Bool ?? AppConfig.LoggingConfig.default.enableFileLogging,
            directory: expandPath(loggingDict["directory"] as? String ?? AppConfig.LoggingConfig.default.directory),
            retentionDays: extractInt(loggingDict["retentionDays"], default: AppConfig.LoggingConfig.default.retentionDays),
            cleanupIntervalHours: extractInt(loggingDict["cleanupIntervalHours"], default: AppConfig.LoggingConfig.default.cleanupIntervalHours),
            level: loggingDict["level"] as? String ?? AppConfig.LoggingConfig.default.level
        )

        return AppConfig(
            output: output,
            triggers: triggers,
            metadata: metadata,
            ui: ui,
            capture: capture,
            logging: logging
        )
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

    /// Expand "~" prefix to the user's home directory.
    private static func expandPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    // MARK: - Type Coercion Helpers

    /// Extract a Double from YAML value, handling Int→Double coercion.
    /// YAML parsers may return Int for values like `1` instead of `1.0`.
    private static func extractDouble(_ value: Any?, default defaultValue: Double) -> Double {
        if let doubleValue = value as? Double {
            return doubleValue
        }
        if let intValue = value as? Int {
            return Double(intValue)
        }
        return defaultValue
    }

    /// Extract an Int from YAML value, handling Double→Int coercion.
    /// YAML parsers may return Double for values like `1280.0` instead of `1280`.
    private static func extractInt(_ value: Any?, default defaultValue: Int) -> Int {
        if let intValue = value as? Int {
            return intValue
        }
        if let doubleValue = value as? Double {
            return Int(doubleValue)
        }
        return defaultValue
    }
}
