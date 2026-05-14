import Cocoa
import ScreenSaver

class AppDelegate: NSObject, NSApplicationDelegate, NSToolbarDelegate {

    var window: NSWindow!
    var saverView: ScreenSaverView!
    var saverClass: ScreenSaverView.Type!
    var isPreview = false

    private let optionsID  = NSToolbarItem.Identifier("options")
    private let previewID  = NSToolbarItem.Identifier("preview")
    private let restartID  = NSToolbarItem.Identifier("restart")

    // MARK: - Launch

    func applicationDidFinishLaunching(_ note: Notification) {
        loadSaverClass()
        buildWindow()
        buildSaverView()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Setup

    private func loadSaverClass() {
        let path = Bundle.main.builtInPlugInsPath! + "/DepartureBoardSaver.saver"
        guard let bundle = Bundle(path: path),
              let cls = bundle.principalClass as? ScreenSaverView.Type else {
            fatalError("Couldn't load saver bundle at \(path)")
        }
        saverClass = cls
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Screensaver Test"
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()

        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsDisplayModeCustomization = false
        window.toolbar = toolbar
        window.makeKeyAndOrderFront(nil)
    }

    // Tears down and recreates the saver view — call after toggling isPreview
    // or after the configure sheet is dismissed so new settings take effect.
    private func buildSaverView() {
        saverView?.stopAnimation()

        let frame = window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        saverView = saverClass.init(frame: frame, isPreview: isPreview)!
        saverView.autoresizingMask = [.width, .height]
        saverView.startAnimation()

        window.contentView = saverView
        window.title = isPreview ? "DepartureBoardSaver — System Settings Preview" : "DepartureBoardSaver Debug - Main Screensaver"

        // Keep the Options button state in sync
        window.toolbar?.items
            .first(where: { $0.itemIdentifier == optionsID })?
            .isEnabled = saverView.hasConfigureSheet
    }

    // MARK: - Actions

    @objc private func openOptions(_ sender: Any?) {
        guard saverView.hasConfigureSheet, let sheet = saverView.configureSheet else {
            let alert = NSAlert()
            alert.messageText = "No configure sheet"
            alert.informativeText = "hasConfigureSheet returned false for this screensaver."
            alert.beginSheetModal(for: window)
            return
        }

        // Present exactly as System Settings does — modal sheet on the window.
        window.beginSheet(sheet) { [weak self] _ in
            // Sheet dismissed (user hit OK or Cancel inside the saver's own sheet).
            // Rebuild so any changed UserDefaults/preferences are picked up.
            self?.buildSaverView()
        }
    }

    @objc private func togglePreview(_ sender: NSSwitch) {
        isPreview = sender.state == .on
        buildSaverView()
    }

    @objc private func restartAnimation(_ sender: Any?) {
        buildSaverView()
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, previewID, .space, restartID, optionsID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [previewID, optionsID, restartID, .flexibleSpace, .space]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier id: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar: Bool
    ) -> NSToolbarItem? {
        switch id {

        case optionsID:
            let item = NSToolbarItem(itemIdentifier: id)
            item.label   = "Options"
            item.toolTip = "Open the screensaver's configure sheet"
            item.image   = NSImage(systemSymbolName: "slider.horizontal.3",
                                   accessibilityDescription: "Options")
            item.target  = self
            item.action  = #selector(openOptions)
            // Enabled state is set properly in buildSaverView() once the view exists
            return item

        case previewID:
            let item   = NSToolbarItem(itemIdentifier: id)
            item.label = "Simulate Settings Preview"
            item.toolTip = "Simulate the small preview shown in System Settings"
            let nsSwitch = NSSwitch()
            nsSwitch.target = self
            nsSwitch.action = #selector(togglePreview)
            nsSwitch.state = isPreview ? .on : .off
            item.view = nsSwitch
            return item

        case restartID:
            let item = NSToolbarItem(itemIdentifier: id)
            item.label   = "Restart"
            item.toolTip = "Tear down and restart the animation"
            item.image   = NSImage(systemSymbolName: "arrow.clockwise",
                                   accessibilityDescription: "Restart")
            item.target  = self
            item.action  = #selector(restartAnimation)
            return item

        default:
            return nil
        }
    }
}
