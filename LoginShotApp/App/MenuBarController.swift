import AppKit

/// Manages the NSStatusItem menu bar icon and its menu.
/// Created only when config ui.menuBarIcon is true.
@MainActor
final class MenuBarController: NSObject {

    private var statusItem: NSStatusItem?
    private let onCaptureNow: @MainActor () -> Void
    private let onReloadConfig: @MainActor () -> Void
    private let onGenerateConfig: @MainActor () -> Void
    private let outputDirectoryProvider: @MainActor () -> String

    init(
        outputDirectoryProvider: @escaping @MainActor () -> String,
        onCaptureNow: @escaping @MainActor () -> Void,
        onReloadConfig: @escaping @MainActor () -> Void,
        onGenerateConfig: @escaping @MainActor () -> Void
    ) {
        self.outputDirectoryProvider = outputDirectoryProvider
        self.onCaptureNow = onCaptureNow
        self.onReloadConfig = onReloadConfig
        self.onGenerateConfig = onGenerateConfig
        super.init()
    }

    /// Show the status bar icon and build the menu.
    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "camera.fill",
                accessibilityDescription: "LoginShot"
            )
        }

        let menu = NSMenu(title: "LoginShot")

        let captureItem = NSMenuItem(
            title: "Capture Now",
            action: #selector(captureNowAction(_:)),
            keyEquivalent: ""
        )
        captureItem.target = self
        menu.addItem(captureItem)

        let openItem = NSMenuItem(
            title: "Open Output Folder",
            action: #selector(openOutputFolderAction(_:)),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let reloadItem = NSMenuItem(
            title: "Reload Config",
            action: #selector(reloadConfigAction(_:)),
            keyEquivalent: ""
        )
        reloadItem.target = self
        menu.addItem(reloadItem)

        let generateItem = NSMenuItem(
            title: "Generate Sample Config",
            action: #selector(generateConfigAction(_:)),
            keyEquivalent: ""
        )
        generateItem.target = self
        menu.addItem(generateItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitAction(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        self.statusItem = item

        Log.ui.info("Menu bar icon enabled")
    }

    /// Remove the status bar icon.
    func teardown() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
            Log.ui.info("Menu bar icon removed")
        }
    }

    // MARK: - Actions

    @objc private func captureNowAction(_ sender: Any?) {
        Log.ui.info("Menu: Capture Now")
        onCaptureNow()
    }

    @objc private func openOutputFolderAction(_ sender: Any?) {
        Log.ui.info("Menu: Open Output Folder")
        let url = URL(fileURLWithPath: outputDirectoryProvider(), isDirectory: true)
        NSWorkspace.shared.open(url)
    }

    @objc private func reloadConfigAction(_ sender: Any?) {
        Log.ui.info("Menu: Reload Config")
        onReloadConfig()
    }

    @objc private func generateConfigAction(_ sender: Any?) {
        Log.ui.info("Menu: Generate Sample Config")
        onGenerateConfig()
    }

    @objc private func quitAction(_ sender: Any?) {
        Log.ui.info("Menu: Quit")
        NSApplication.shared.terminate(nil)
    }
}
