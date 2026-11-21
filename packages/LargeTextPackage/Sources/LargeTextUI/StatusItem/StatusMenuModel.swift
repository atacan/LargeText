import LargeTextCore

/// The status menu's contents (§2.6, §2.7). Pure.
package enum StatusMenuModel {
    /// - Parameters:
    ///   - readerHotkey: shown in "Read Text Under Pointer (…)"; `nil` leaves that item out.
    ///   - hotkeyUnavailable: one disabled "Shortcut … unavailable" row each.
    package static func items(
        hotkey: KeyCombo,
        readerHotkey: KeyCombo?,
        permissions: Permissions,
        hotkeyUnavailable: [KeyCombo]
    ) -> [StatusMenuItem] {
        var items: [StatusMenuItem] = [
            .action(title: "Open Large Editor (\(KeyComboFormatter.string(for: hotkey)))", action: .openEditor),
        ]
        if let readerHotkey {
            items.append(.action(
                title: "Read Text Under Pointer (\(KeyComboFormatter.string(for: readerHotkey)))",
                action: .readTextUnderPointer
            ))
        }
        items.append(permissionItem(permissions))
        for combo in hotkeyUnavailable {
            items.append(.info(title: "Shortcut \(KeyComboFormatter.string(for: combo)) unavailable"))
        }
        items.append(.action(title: "Settings…", action: .openSettings))
        items.append(.separator)
        items.append(.action(title: "Quit LargeText", action: .quit))
        return items
    }

    /// With ⌘, shown in the menu and active while it is open.
    package static func keyEquivalent(for action: StatusMenuAction) -> String {
        switch action {
        case .openSettings: ","
        case .quit: "q"
        case .openEditor, .readTextUnderPointer, .grantAccess, .relaunch: ""
        }
    }

    package static func permissionItem(_ permissions: Permissions) -> StatusMenuItem {
        switch permissions.setup {
        case .granted:
            .info(title: "Accessibility: Granted ✓")
        case .needsRelaunch:
            .action(title: "Relaunch to finish setup", action: .relaunch)
        case .needsGrant:
            .action(title: "Grant Access…", action: .grantAccess)
        }
    }
}
