import Foundation
import OSLog

enum FileLogLevel: Int {
    case trace = 0
    case debug = 1
    case information = 2
    case warning = 3
    case error = 4
    case critical = 5
    case none = 6

    static func parse(_ value: String) -> FileLogLevel {
        switch value.lowercased() {
        case "trace": .trace
        case "debug": .debug
        case "information": .information
        case "warning": .warning
        case "error": .error
        case "critical": .critical
        case "none": .none
        default: .information
        }
    }

    var label: String {
        switch self {
        case .trace: "Trace"
        case .debug: "Debug"
        case .information: "Information"
        case .warning: "Warning"
        case .error: "Error"
        case .critical: "Critical"
        case .none: "None"
        }
    }
}

actor FileLogger {
    static let shared = FileLogger()

    private var isEnabled = false
    private var directory = ("~/Library/Logs/LoginShot" as NSString).expandingTildeInPath
    private var minimumLevel: FileLogLevel = .information
    private var retentionDays = 14
    private var cleanupIntervalHours = 24
    private var cleanupTask: Task<Void, Never>?

    func configure(
        enabled: Bool,
        directory: String,
        retentionDays: Int,
        cleanupIntervalHours: Int,
        level: String
    ) {
        isEnabled = enabled
        self.directory = directory
        self.retentionDays = max(1, retentionDays)
        self.cleanupIntervalHours = max(1, cleanupIntervalHours)
        minimumLevel = FileLogLevel.parse(level)

        cleanupTask?.cancel()
        guard isEnabled else { return }

        ensureDirectory()
        cleanupNow()
        cleanupTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double(cleanupIntervalHours * 3600)))
                cleanupNow()
            }
        }
    }

    func currentLogPath() -> String? {
        guard isEnabled else { return nil }
        return dailyLogPath(for: Date())
    }

    func write(level: FileLogLevel, category: String, message: String) {
        guard isEnabled else { return }
        guard level.rawValue >= minimumLevel.rawValue else { return }
        guard minimumLevel != .none else { return }

        ensureDirectory()
        let path = dailyLogPath(for: Date())
        let line = "\(timestampString()) [\(level.label)] \(category): \(message)\n"

        if let data = line.data(using: .utf8),
            FileManager.default.fileExists(atPath: path),
            let fileHandle = FileHandle(forWritingAtPath: path) {
            _ = try? fileHandle.seekToEnd()
            try? fileHandle.write(contentsOf: data)
            try? fileHandle.close()
            return
        }

        try? line.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func cleanupNow() {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: retentionDays * -1, to: Date()) ?? Date.distantPast
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        for file in files where file.hasPrefix("loginshot-") && file.hasSuffix(".log") {
            let path = (directory as NSString).appendingPathComponent(file)
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let modified = attrs[FileAttributeKey.modificationDate] as? Date else {
                continue
            }
            if modified < cutoffDate {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }

    private func dailyLogPath(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let name = "loginshot-\(formatter.string(from: date)).log"
        return (directory as NSString).appendingPathComponent(name)
    }

    private func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS ZZZZZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}

struct AppLogger {
    private let osLogger: Logger
    private let category: String

    init(category: String) {
        self.osLogger = Logger(subsystem: "dev.pruiz.LoginShot", category: category)
        self.category = category
    }

    func trace(_ message: String) {
        osLogger.debug("\(message, privacy: .public)")
        Task { await FileLogger.shared.write(level: .trace, category: category, message: message) }
    }

    func debug(_ message: String) {
        osLogger.debug("\(message, privacy: .public)")
        Task { await FileLogger.shared.write(level: .debug, category: category, message: message) }
    }

    func info(_ message: String) {
        osLogger.info("\(message, privacy: .public)")
        Task { await FileLogger.shared.write(level: .information, category: category, message: message) }
    }

    func warning(_ message: String) {
        osLogger.warning("\(message, privacy: .public)")
        Task { await FileLogger.shared.write(level: .warning, category: category, message: message) }
    }

    func error(_ message: String) {
        osLogger.error("\(message, privacy: .public)")
        Task { await FileLogger.shared.write(level: .error, category: category, message: message) }
    }
}

/// Centralized loggers for LoginShot subsystems.
enum Log {
    static let app = AppLogger(category: "app")
    static let capture = AppLogger(category: "capture")
    static let config = AppLogger(category: "config")
    static let storage = AppLogger(category: "storage")
    static let triggers = AppLogger(category: "triggers")
    static let ui = AppLogger(category: "ui")

    static func configureFileLogging(
        enabled: Bool,
        directory: String,
        retentionDays: Int,
        cleanupIntervalHours: Int,
        level: String
    ) {
        Task {
            await FileLogger.shared.configure(
                enabled: enabled,
                directory: directory,
                retentionDays: retentionDays,
                cleanupIntervalHours: cleanupIntervalHours,
                level: level
            )
        }
    }
}
