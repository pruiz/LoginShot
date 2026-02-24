import Foundation
import XCTest
@testable import LoginShot

final class StartupRegistrationServiceTests: XCTestCase {
    private var tempDirectory: URL!
    private var fakeLaunchctl: FakeLaunchctlController!
    private var executablePath: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("StartupRegistrationServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let executableURL = tempDirectory.appendingPathComponent("LoginShot")
        FileManager.default.createFile(atPath: executableURL.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        executablePath = executableURL.path

        fakeLaunchctl = FakeLaunchctlController()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        fakeLaunchctl = nil
        executablePath = nil
        super.tearDown()
    }

    func testEnableWritesPlistAndBootstrapsService() throws {
        let service = makeService()

        try service.setEnabled(true)

        let plistPath = launchAgentPlistPath()
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistPath))

        let content = try String(contentsOfFile: plistPath, encoding: .utf8)
        XCTAssertTrue(content.contains(executablePath))
        XCTAssertEqual(fakeLaunchctl.calls, [
            "bootout gui/501 \(plistPath)",
            "bootstrap gui/501 \(plistPath)",
            "kickstart gui/501 dev.pruiz.LoginShot"
        ])
    }

    func testDisableRemovesPlistAndBootsOutService() throws {
        let service = makeService()
        try service.setEnabled(true)
        fakeLaunchctl.calls.removeAll()

        try service.setEnabled(false)

        XCTAssertFalse(FileManager.default.fileExists(atPath: launchAgentPlistPath()))
        XCTAssertEqual(fakeLaunchctl.calls, ["bootout gui/501 \(launchAgentPlistPath())"])
    }

    func testIsEnabledUsesLoadedServiceState() {
        fakeLaunchctl.loaded = true
        let service = makeService()

        XCTAssertTrue(service.isEnabled())
    }

    func testIsEnabledFallsBackToPlistPresence() throws {
        let service = makeService()
        try service.setEnabled(true)
        fakeLaunchctl.loaded = false

        XCTAssertTrue(service.isEnabled())
    }

    func testEnableThrowsWhenExecutableMissing() {
        let service = StartupRegistrationService(
            launchctl: fakeLaunchctl,
            homeDirectoryPath: tempDirectory.path,
            executablePath: tempDirectory.appendingPathComponent("missing").path,
            guiUID: "gui/501"
        )

        XCTAssertThrowsError(try service.setEnabled(true))
    }

    private func makeService() -> StartupRegistrationService {
        StartupRegistrationService(
            launchctl: fakeLaunchctl,
            homeDirectoryPath: tempDirectory.path,
            executablePath: executablePath,
            guiUID: "gui/501"
        )
    }

    private func launchAgentPlistPath() -> String {
        tempDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
            .appendingPathComponent("dev.pruiz.LoginShot.plist")
            .path
    }
}

private final class FakeLaunchctlController: LaunchctlControlling, @unchecked Sendable {
    var calls: [String] = []
    var loaded = false

    func bootstrap(guiUID: String, plistPath: String) throws {
        calls.append("bootstrap \(guiUID) \(plistPath)")
        loaded = true
    }

    func bootout(guiUID: String, plistPath: String) throws {
        calls.append("bootout \(guiUID) \(plistPath)")
        loaded = false
    }

    func kickstart(guiUID: String, label: String) throws {
        calls.append("kickstart \(guiUID) \(label)")
    }

    func isServiceLoaded(guiUID: String, label: String) -> Bool {
        loaded
    }
}
