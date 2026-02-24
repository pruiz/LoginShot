import Foundation

protocol StartupRegistrationManaging: Sendable {
    func isEnabled() -> Bool
    func setEnabled(_ enabled: Bool) throws
}

enum StartupRegistrationError: LocalizedError {
    case missingExecutable(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable(let path):
            return "LoginShot executable not found or not executable at \(path)"
        }
    }
}

protocol LaunchctlControlling: Sendable {
    func bootstrap(guiUID: String, plistPath: String) throws
    func bootout(guiUID: String, plistPath: String) throws
    func kickstart(guiUID: String, label: String) throws
    func isServiceLoaded(guiUID: String, label: String) -> Bool
}

struct LaunchctlController: LaunchctlControlling {
    func bootstrap(guiUID: String, plistPath: String) throws {
        try run(["bootstrap", guiUID, plistPath])
    }

    func bootout(guiUID: String, plistPath: String) throws {
        try run(["bootout", guiUID, plistPath])
    }

    func kickstart(guiUID: String, label: String) throws {
        try run(["kickstart", "-k", "\(guiUID)/\(label)"])
    }

    func isServiceLoaded(guiUID: String, label: String) -> Bool {
        let status = runAllowingFailure(["print", "\(guiUID)/\(label)"])
        return status == 0
    }

    private func run(_ arguments: [String]) throws {
        let status = runAllowingFailure(arguments)
        guard status == 0 else {
            throw NSError(
                domain: "LoginShot.Launchctl",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "launchctl \(arguments.joined(separator: " ")) failed with exit code \(status)"]
            )
        }
    }

    @discardableResult
    private func runAllowingFailure(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}

struct StartupRegistrationService: StartupRegistrationManaging, @unchecked Sendable {
    private let label: String
    private let launchctl: LaunchctlControlling
    private let fileManager: FileManager
    private let homeDirectoryPath: String
    private let executablePath: String
    private let guiUID: String

    init(
        label: String = "dev.pruiz.LoginShot",
        launchctl: LaunchctlControlling = LaunchctlController(),
        fileManager: FileManager = .default,
        homeDirectoryPath: String = NSHomeDirectory(),
        executablePath: String = Bundle.main.executablePath ?? "",
        guiUID: String = "gui/\(getuid())"
    ) {
        self.label = label
        self.launchctl = launchctl
        self.fileManager = fileManager
        self.homeDirectoryPath = homeDirectoryPath
        self.executablePath = executablePath
        self.guiUID = guiUID
    }

    func isEnabled() -> Bool {
        if launchctl.isServiceLoaded(guiUID: guiUID, label: label) {
            return true
        }
        return fileManager.fileExists(atPath: plistPath)
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try install()
        } else {
            uninstall()
        }
    }

    private var launchAgentsDirectory: String {
        (homeDirectoryPath as NSString).appendingPathComponent("Library/LaunchAgents")
    }

    private var logDirectory: String {
        (homeDirectoryPath as NSString).appendingPathComponent("Library/Logs/LoginShot")
    }

    private var plistPath: String {
        (launchAgentsDirectory as NSString).appendingPathComponent("\(label).plist")
    }

    private var stdoutPath: String {
        (logDirectory as NSString).appendingPathComponent("agent.out.log")
    }

    private var stderrPath: String {
        (logDirectory as NSString).appendingPathComponent("agent.err.log")
    }

    private func install() throws {
        guard fileManager.isExecutableFile(atPath: executablePath) else {
            throw StartupRegistrationError.missingExecutable(executablePath)
        }

        try fileManager.createDirectory(atPath: launchAgentsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(atPath: logDirectory, withIntermediateDirectories: true)

        let plist = renderedPlist()
        try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)

        try? launchctl.bootout(guiUID: guiUID, plistPath: plistPath)
        try launchctl.bootstrap(guiUID: guiUID, plistPath: plistPath)
        try launchctl.kickstart(guiUID: guiUID, label: label)
    }

    private func uninstall() {
        try? launchctl.bootout(guiUID: guiUID, plistPath: plistPath)
        if fileManager.fileExists(atPath: plistPath) {
            try? fileManager.removeItem(atPath: plistPath)
        }
    }

    private func renderedPlist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(xmlEscaped(label))</string>

            <key>ProgramArguments</key>
            <array>
                <string>\(xmlEscaped(executablePath))</string>
            </array>

            <key>RunAtLoad</key>
            <true/>

            <key>KeepAlive</key>
            <false/>

            <key>ProcessType</key>
            <string>Interactive</string>

            <key>StandardOutPath</key>
            <string>\(xmlEscaped(stdoutPath))</string>

            <key>StandardErrorPath</key>
            <string>\(xmlEscaped(stderrPath))</string>
        </dict>
        </plist>
        """
    }

    private func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
