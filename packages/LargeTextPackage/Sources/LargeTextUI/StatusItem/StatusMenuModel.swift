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
