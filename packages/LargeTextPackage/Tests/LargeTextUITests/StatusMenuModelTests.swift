import LargeTextCore
import Testing
@testable import LargeTextUI

@Suite("StatusMenuModel")
struct StatusMenuModelTests {
    private let readerItem = StatusMenuItem.action(title: "Read Text Under Pointer (⌃⌥⌘R)", action: .readTextUnderPointer)
    private let settingsItem = StatusMenuItem.action(title: "Settings…", action: .openSettings)

    @Test func menuWithAllPermissions() {
        let items = StatusMenuModel.items(
            hotkey: .default,
            readerHotkey: .readerDefault,
            permissions: .allGranted,
            hotkeyUnavailable: []
        )
        #expect(items == [
            .action(title: "Open Large Editor (⌃⌥⌘T)", action: .openEditor),
            readerItem,
            .info(title: "Accessibility: Granted ✓"),
            settingsItem,
            .separator,
            .action(title: "Quit LargeText", action: .quit),
        ])
    }

    @Test func readerItemShowsTheConfiguredCombo() {
        let combo = KeyCombo(keyCode: 0x0D, modifiers: [.control, .shift])
        let items = StatusMenuModel.items(hotkey: .default, readerHotkey: combo, permissions: .allGranted, hotkeyUnavailable: [])
        #expect(items.contains(.action(title: "Read Text Under Pointer (⌃⇧W)", action: .readTextUnderPointer)))
    }

    /// The reader turned off (Settings plan D1).
    @Test func noReaderComboLeavesTheItemOut() {
        let items = StatusMenuModel.items(hotkey: .default, readerHotkey: nil, permissions: .allGranted, hotkeyUnavailable: [])
        #expect(items == [
            .action(title: "Open Large Editor (⌃⌥⌘T)", action: .openEditor),
            .info(title: "Accessibility: Granted ✓"),
            settingsItem,
            .separator,
            .action(title: "Quit LargeText", action: .quit),
        ])
    }

    @Test func menuShowsHotkeyError() {
        let items = StatusMenuModel.items(
            hotkey: .default,
            readerHotkey: .readerDefault,
            permissions: .allGranted,
            hotkeyUnavailable: [.default]
        )
        #expect(items.contains(.info(title: "Shortcut ⌃⌥⌘T unavailable")))
    }

    @Test func menuListsSeveralUnavailableCombos() {
        let items = StatusMenuModel.items(
            hotkey: .default,
            readerHotkey: .readerDefault,
            permissions: .allGranted,
            hotkeyUnavailable: [.default, .readerDefault]
        )
        #expect(items == [
            .action(title: "Open Large Editor (⌃⌥⌘T)", action: .openEditor),
            readerItem,
            .info(title: "Accessibility: Granted ✓"),
            .info(title: "Shortcut ⌃⌥⌘T unavailable"),
            .info(title: "Shortcut ⌃⌥⌘R unavailable"),
            settingsItem,
            .separator,
            .action(title: "Quit LargeText", action: .quit),
        ])
    }

    @Test func permissionItemStates() {
        #expect(StatusMenuModel.permissionItem(.allDenied) == .action(title: "Grant Access…", action: .grantAccess))
        #expect(
            StatusMenuModel.permissionItem(Permissions(accessibility: .denied, eventPosting: .granted))
                == .action(title: "Grant Access…", action: .grantAccess)
        )
        #expect(
            StatusMenuModel.permissionItem(Permissions(accessibility: .granted, eventPosting: .denied))
                == .action(title: "Relaunch to finish setup", action: .relaunch)
        )
    }

    /// Settings plan §3.2: "Settings…" right before the separator and Quit, whatever else is listed.
    @Test func settingsItemPrecedesTheSeparatorAndQuit() {
        let items = StatusMenuModel.items(
            hotkey: .default,
            readerHotkey: nil,
            permissions: .allDenied,
            hotkeyUnavailable: [.default]
        )
        #expect(Array(items.suffix(3)) == [settingsItem, .separator, .action(title: "Quit LargeText", action: .quit)])
    }

    @Test func keyEquivalents() {
        #expect(StatusMenuModel.keyEquivalent(for: .openSettings) == ",")
        #expect(StatusMenuModel.keyEquivalent(for: .quit) == "q")
        #expect(StatusMenuModel.keyEquivalent(for: .openEditor) == "")
        #expect(StatusMenuModel.keyEquivalent(for: .grantAccess) == "")
    }
}

/// `StatusItemController.perform`, without installing the status item.
@MainActor
@Suite("StatusItemController actions")
struct StatusItemControllerActionTests {
    @MainActor
    final class RecordingPermissions: PermissionsProviding {
        var current = Permissions.allDenied
        private(set) var calls: [String] = []

        func requestAccessibility() { calls.append("request") }
        func openSystemSettings() { calls.append("openSystemSettings") }
    }

    /// D6: the request adds LargeText to the Accessibility list, then the pane opens, as in Settings.
    @Test func grantAccessRequestsThenOpensSystemSettings() {
        let permissions = RecordingPermissions()
        let controller = StatusItemController(hotkey: .default, permissions: permissions, onOpenEditor: {})

        controller.perform(.grantAccess)

        #expect(permissions.calls == ["request", "openSystemSettings"])
        #expect(!controller.isInstalled)
    }

    @Test func settingsCallsOnOpenSettings() {
        var opened = 0
        let controller = StatusItemController(
            hotkey: .default,
            permissions: RecordingPermissions(),
            onOpenEditor: {},
            onOpenSettings: { opened += 1 }
        )

        controller.perform(.openSettings)

        #expect(opened == 1)
    }
}
