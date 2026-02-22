import AppKit

// LoginShot — macOS agent app entrypoint.
// Uses NSApplication directly (no SwiftUI) for a lightweight agent/menu-bar app.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
