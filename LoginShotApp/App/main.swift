import AppKit

// LoginShot — macOS agent app entrypoint.
// Uses NSApplication directly (no SwiftUI) for a lightweight agent/menu-bar app.

// Detect if running under XCTest by checking for test configuration.
// When testing, we skip creating AppDelegate to avoid triggering
// camera permissions and other production-only side effects.
// Tests instantiate AppDelegate directly with mock dependencies.
let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

let app = NSApplication.shared

if isRunningTests {
    // Minimal setup for test runner - need a run loop but no app delegate
    app.setActivationPolicy(.prohibited)
} else {
    let delegate = AppDelegate()
    app.delegate = delegate
}

app.run()
