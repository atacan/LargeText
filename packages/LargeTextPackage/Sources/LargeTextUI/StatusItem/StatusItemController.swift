import AppKit
import LargeTextCore

/// The menu-bar item (§2.6, §2.7). Driven by Kit: `install()` in `start()`, `remove()` in `stop()`.
/// The menu is rebuilt from `StatusMenuModel` every time it opens, so permissions are always fresh.
@MainActor
package final class StatusItemController: NSObject, NSMenuDelegate {
    /// Shown in the "Open Large Editor (…)" title.
    package var hotkey: KeyCombo
    /// Shown in the "Read Text Under Pointer (…)" title; `nil` leaves that item out.
    package var readerHotkey: KeyCombo?
    /// One disabled "Shortcut … unavailable" row per combo.
    package var hotkeyUnavailable: [KeyCombo] = []

    private let permissions: any PermissionsProviding
    private let onOpenEditor: @MainActor () -> Void
    private let onReadTextUnderPointer: (@MainActor () -> Void)?
    private let onOpenSettings: (@MainActor () -> Void)?
    private var statusItem: NSStatusItem?

    package init(
        hotkey: KeyCombo,
        readerHotkey: KeyCombo? = nil,
        permissions: any PermissionsProviding,
        onOpenEditor: @escaping @MainActor () -> Void,
        onReadTextUnderPointer: (@MainActor () -> Void)? = nil,
        onOpenSettings: (@MainActor () -> Void)? = nil
    ) {
        self.hotkey = hotkey
        self.readerHotkey = readerHotkey
        self.permissions = permissions
        self.onOpenEditor = onOpenEditor
        self.onReadTextUnderPointer = onReadTextUnderPointer
        self.onOpenSettings = onOpenSettings
        super.init()
    }

    package var isInstalled: Bool { statusItem != nil }

    /// Creates the `NSStatusItem`. Idempotent.
    package func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "textformat.size", accessibilityDescription: "LargeText")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "LargeText"
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        statusItem = item
        rebuild(menu)
    }

    package func remove() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    // MARK: - NSMenuDelegate

    package func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    // MARK: - Private

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        let items = StatusMenuModel.items(
            hotkey: hotkey,
            readerHotkey: readerHotkey,
            permissions: permissions.current,
            hotkeyUnavailable: hotkeyUnavailable
        )
        for item in items {
            menu.addItem(makeMenuItem(item))
        }
    }

    private func makeMenuItem(_ item: StatusMenuItem) -> NSMenuItem {
        switch item {
        case .separator:
            return .separator()
        case .info(let title):
            let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            menuItem.isEnabled = false
            return menuItem
        case .action(let title, let action):
            let menuItem = NSMenuItem(title: title, action: selector(for: action), keyEquivalent: StatusMenuModel.keyEquivalent(for: action))
            menuItem.target = self
            menuItem.isEnabled = true
            return menuItem
        }
    }

    /// What choosing a menu item does.
    package func perform(_ action: StatusMenuAction) {
        switch action {
        case .openEditor:
            onOpenEditor()
        case .readTextUnderPointer:
            onReadTextUnderPointer?()
        case .openSettings:
            onOpenSettings?()
        case .grantAccess:
            // D6, as in Settings: the request adds LargeText to the Accessibility list (and prompts while it
            // isn't trusted); the pane then shows it there.
            permissions.requestAccessibility()
            permissions.openSystemSettings()
        case .relaunch:
            AppRelauncher.relaunch(onFailure: { [permissions] in permissions.openSystemSettings() })
        case .quit:
            NSApp.terminate(nil)
        }
    }

    private func selector(for action: StatusMenuAction) -> Selector {
        switch action {
        case .openEditor: #selector(openEditor(_:))
        case .readTextUnderPointer: #selector(readTextUnderPointer(_:))
        case .openSettings: #selector(openSettings(_:))
        case .grantAccess: #selector(grantAccess(_:))
        case .relaunch: #selector(relaunch(_:))
        case .quit: #selector(quit(_:))
        }
    }

    @objc private func openEditor(_ sender: Any?) { perform(.openEditor) }
    @objc private func readTextUnderPointer(_ sender: Any?) { perform(.readTextUnderPointer) }
    @objc private func openSettings(_ sender: Any?) { perform(.openSettings) }
    @objc private func grantAccess(_ sender: Any?) { perform(.grantAccess) }
    @objc private func relaunch(_ sender: Any?) { perform(.relaunch) }
    @objc private func quit(_ sender: Any?) { perform(.quit) }
}
