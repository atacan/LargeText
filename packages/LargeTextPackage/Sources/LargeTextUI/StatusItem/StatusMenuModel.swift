import LargeTextCore

/// The status menu's contents (§2.6, §2.7). Pure.
package enum StatusMenuModel {
    package static func items(
        hotkey: KeyCombo,
        permissions: Permissions,
        hotkeyUnavailable: KeyCombo?
    ) -> [StatusMenuItem] {
        var items: [StatusMenuItem] = [
            .action(title: "Open Large Editor (\(KeyComboFormatter.string(for: hotkey)))", action: .openEditor),
            permissionItem(permissions),
        ]
        if let hotkeyUnavailable {
            items.append(.info(title: "Shortcut \(KeyComboFormatter.string(for: hotkeyUnavailable)) unavailable"))
        }
        items.append(.separator)
        items.append(.action(title: "Quit LargeText", action: .quit))
        return items
    }

    package static func permissionItem(_ permissions: Permissions) -> StatusMenuItem {
        switch (permissions.accessibility, permissions.eventPosting) {
        case (.granted, .granted):
            .info(title: "Accessibility: Granted ✓")
        case (.granted, .denied):
            // Spike 0i: posting may only start working after a relaunch.
            .action(title: "Relaunch to finish setup", action: .relaunch)
        case (.denied, _):
            .action(title: "Grant Access…", action: .grantAccess)
        }
    }
}
