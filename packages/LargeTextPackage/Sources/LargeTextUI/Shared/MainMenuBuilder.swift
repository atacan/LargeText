import AppKit

/// The minimal main menu (Settings plan §3.3). The app only has a Dock icon and a menu bar while Settings is
/// open, and an empty app menu would look broken there. Kit installs it once, at startup.
///
/// The menu also gives the Settings window ⌘W, ⌘Q and the edit keys. The editor and reader panels never
/// reach it for their own keys: AppKit asks the key window before the main menu, and their text views
/// handle their ⌘-shortcuts there. The app commands (About, Check for Updates…, Settings…, Hide, Quit) are disabled while a
/// panel is key, so an unhandled ⌘Q or ⌘H in the editor does nothing, as it did before this menu existed.
@MainActor
package final class MainMenuBuilder: NSObject, NSMenuItemValidation {
    package static let appName = "LargeText"

    private let onOpenSettings: @MainActor () -> Void
    private let onCheckForUpdates: (@MainActor () -> Void)?
    private let allowsAppCommands: @MainActor () -> Bool

    /// - Parameters:
    ///   - onOpenSettings: "Settings…" (⌘,).
    ///   - onCheckForUpdates: "Check for Updates…"; `nil` leaves it out.
    ///   - allowsAppCommands: whether About, Settings…, Hide and Quit are enabled; by default, unless a panel
    ///     (the editor or the pinned reader) is the key window.
    package init(
        onOpenSettings: @escaping @MainActor () -> Void,
        onCheckForUpdates: (@MainActor () -> Void)? = nil,
        allowsAppCommands: @escaping @MainActor () -> Bool = { !(NSApp.keyWindow is NSPanel) }
    ) {
        self.onOpenSettings = onOpenSettings
        self.onCheckForUpdates = onCheckForUpdates
        self.allowsAppCommands = allowsAppCommands
        super.init()
    }

    /// Sets `NSApp.mainMenu`. The menu items target this object weakly, so the caller keeps it alive.
    package func install() {
        NSApp.mainMenu = makeMenu()
    }

    /// The LargeText, Edit and Window menus.
    package func makeMenu() -> NSMenu {
        let main = NSMenu(title: "Main Menu")
        for submenu in [appMenu(), editMenu(), windowMenu()] {
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            main.addItem(item)
        }
        return main
    }

    // MARK: - Menus

    private func appMenu() -> NSMenu {
        let menu = NSMenu(title: Self.appName)
        menu.addItem(item("About \(Self.appName)", #selector(about(_:)), target: self))
        if onCheckForUpdates != nil {
            menu.addItem(item("Check for Updates…", #selector(checkForUpdates(_:)), target: self))
        }
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings(_:)), ",", target: self))
        menu.addItem(.separator())
        menu.addItem(item("Hide \(Self.appName)", #selector(hide(_:)), "h", target: self))
        menu.addItem(.separator())
        menu.addItem(item("Quit \(Self.appName)", #selector(quit(_:)), "q", target: self))
        return menu
    }

    /// Standard selectors through the responder chain, so they act on whatever field has focus.
    private func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        return menu
    }

    /// Through the responder chain to the key window. The panels can't be minimized or closed, so AppKit
    /// disables both for them.
    private func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        return menu
    }

    private func item(
        _ title: String,
        _ action: Selector,
        _ keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }

    // MARK: - Actions

    @objc private func about(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(sender)
    }

    @objc private func openSettings(_ sender: Any?) {
        onOpenSettings()
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        onCheckForUpdates?()
    }

    @objc private func hide(_ sender: Any?) {
        NSApp.hide(sender)
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    // MARK: - NSMenuItemValidation

    /// Only reached for the app commands, which target this object.
    package func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        allowsAppCommands()
    }
}
