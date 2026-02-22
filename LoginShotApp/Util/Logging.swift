import OSLog

/// Centralized loggers for LoginShot subsystems.
enum Log {
    static let app = Logger(subsystem: "dev.pruiz.LoginShot", category: "app")
    static let capture = Logger(subsystem: "dev.pruiz.LoginShot", category: "capture")
    static let config = Logger(subsystem: "dev.pruiz.LoginShot", category: "config")
    static let storage = Logger(subsystem: "dev.pruiz.LoginShot", category: "storage")
    static let triggers = Logger(subsystem: "dev.pruiz.LoginShot", category: "triggers")
    static let ui = Logger(subsystem: "dev.pruiz.LoginShot", category: "ui")
}
