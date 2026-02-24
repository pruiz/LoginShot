import AppKit

/// Manages the NSStatusItem menu bar icon and its menu.
/// Created only when config ui.menuBarIcon is true.
@MainActor
final class MenuBarController: NSObject {

    struct CameraMenuState: Sendable {
        let selectedUniqueID: String?
        let devices: [CameraDeviceDescriptor]
    }

    private var statusItem: NSStatusItem?
    private weak var cameraSubmenu: NSMenu?
    private let onCaptureNow: @MainActor () -> Void
    private let onReloadConfig: @MainActor () -> Void
    private let onEditConfig: @MainActor () -> Void
    private let onGenerateConfig: @MainActor () -> Void
    private let onOpenLog: @MainActor () -> Void
    private let cameraMenuStateProvider: @MainActor () -> CameraMenuState
    private let onSelectCamera: @MainActor (String?) -> Void
    private let onVerifyCamera: @MainActor () -> Void
    private let outputDirectoryProvider: @MainActor () -> String

    init(
        outputDirectoryProvider: @escaping @MainActor () -> String,
        onCaptureNow: @escaping @MainActor () -> Void,
        onReloadConfig: @escaping @MainActor () -> Void,
        onEditConfig: @escaping @MainActor () -> Void,
        onGenerateConfig: @escaping @MainActor () -> Void,
        onOpenLog: @escaping @MainActor () -> Void,
        cameraMenuStateProvider: @escaping @MainActor () -> CameraMenuState,
        onSelectCamera: @escaping @MainActor (String?) -> Void,
        onVerifyCamera: @escaping @MainActor () -> Void
    ) {
        self.outputDirectoryProvider = outputDirectoryProvider
        self.onCaptureNow = onCaptureNow
        self.onReloadConfig = onReloadConfig
        self.onEditConfig = onEditConfig
        self.onGenerateConfig = onGenerateConfig
        self.onOpenLog = onOpenLog
        self.cameraMenuStateProvider = cameraMenuStateProvider
        self.onSelectCamera = onSelectCamera
        self.onVerifyCamera = onVerifyCamera
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

        let cameraItem = NSMenuItem(title: "Camera", action: nil, keyEquivalent: "")
        let cameraSubmenu = NSMenu(title: "Camera")
        cameraSubmenu.delegate = self
        cameraItem.submenu = cameraSubmenu
        menu.addItem(cameraItem)
        self.cameraSubmenu = cameraSubmenu

        rebuildCameraSubmenu(cameraSubmenu)

        menu.addItem(.separator())

        let reloadItem = NSMenuItem(
            title: "Reload Config",
            action: #selector(reloadConfigAction(_:)),
            keyEquivalent: ""
        )
        reloadItem.target = self
        menu.addItem(reloadItem)

        let editItem = NSMenuItem(
            title: "Edit Config",
            action: #selector(editConfigAction(_:)),
            keyEquivalent: ""
        )
        editItem.target = self
        menu.addItem(editItem)

        let generateItem = NSMenuItem(
            title: "Generate Sample Config",
            action: #selector(generateConfigAction(_:)),
            keyEquivalent: ""
        )
        generateItem.target = self
        menu.addItem(generateItem)

        let openLogItem = NSMenuItem(
            title: "Open Log",
            action: #selector(openLogAction(_:)),
            keyEquivalent: ""
        )
        openLogItem.target = self
        menu.addItem(openLogItem)

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

    @objc private func editConfigAction(_ sender: Any?) {
        Log.ui.info("Menu: Edit Config")
        onEditConfig()
    }

    @objc private func generateConfigAction(_ sender: Any?) {
        Log.ui.info("Menu: Generate Sample Config")
        onGenerateConfig()
    }

    @objc private func openLogAction(_ sender: Any?) {
        Log.ui.info("Menu: Open Log")
        onOpenLog()
    }

    @objc private func selectCameraAction(_ sender: NSMenuItem) {
        let uniqueID = sender.representedObject as? String
        Log.ui.info("Menu: Select Camera \(uniqueID ?? "auto")")
        onSelectCamera(uniqueID)
        if let submenu = cameraSubmenu {
            rebuildCameraSubmenu(submenu)
        }
    }

    @objc private func verifyCameraAction(_ sender: Any?) {
        Log.ui.info("Menu: Verify selected camera")
        onVerifyCamera()
    }

    @objc private func quitAction(_ sender: Any?) {
        Log.ui.info("Menu: Quit")
        NSApplication.shared.terminate(nil)
    }

    private func rebuildCameraSubmenu(_ submenu: NSMenu) {
        submenu.removeAllItems()

        let state = cameraMenuStateProvider()

        let autoItem = NSMenuItem(title: "Auto (default)", action: #selector(selectCameraAction(_:)), keyEquivalent: "")
        autoItem.target = self
        autoItem.state = state.selectedUniqueID == nil ? NSControl.StateValue.on : NSControl.StateValue.off
        autoItem.representedObject = nil
        submenu.addItem(autoItem)

        if !state.devices.isEmpty {
            submenu.addItem(.separator())
        }

        for device in state.devices {
            let title = "\(device.deviceName) [\(device.position)]"
            let item = NSMenuItem(title: title, action: #selector(selectCameraAction(_:)), keyEquivalent: "")
            item.target = self
            item.state = state.selectedUniqueID == device.uniqueID ? NSControl.StateValue.on : NSControl.StateValue.off
            item.representedObject = device.uniqueID
            submenu.addItem(item)
        }

        submenu.addItem(.separator())
        let verifyItem = NSMenuItem(title: "Verify selected camera", action: #selector(verifyCameraAction(_:)), keyEquivalent: "")
        verifyItem.target = self
        submenu.addItem(verifyItem)
    }
}

extension MenuBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard menu == cameraSubmenu else { return }
        rebuildCameraSubmenu(menu)
    }
}
