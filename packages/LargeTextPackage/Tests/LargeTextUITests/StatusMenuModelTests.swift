import LargeTextCore
import Testing
@testable import LargeTextUI

@Suite("StatusMenuModel")
struct StatusMenuModelTests {
    private let readerItem = StatusMenuItem.action(title: "Read Text Under Pointer (⌃⌥⌘R)", action: .readTextUnderPointer)

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
            .separator,
            .action(title: "Quit LargeText", action: .quit),
        ])
    }

    @Test func readerItemShowsTheConfiguredCombo() {
        let combo = KeyCombo(keyCode: 0x0D, modifiers: [.control, .shift])
        let items = StatusMenuModel.items(hotkey: .default, readerHotkey: combo, permissions: .allGranted, hotkeyUnavailable: [])
        #expect(items.contains(.action(title: "Read Text Under Pointer (⌃⇧W)", action: .readTextUnderPointer)))
    }

    @Test func noReaderComboLeavesTheItemOut() {
        let items = StatusMenuModel.items(hotkey: .default, readerHotkey: nil, permissions: .allGranted, hotkeyUnavailable: [])
        #expect(!items.contains(readerItem))
        #expect(items.count == 4)
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
}
