import LargeTextCore
import Testing
@testable import LargeTextUI

@Suite("Presentation strings")
struct PresentationStringsTests {
    // MARK: Editor header

    @Test func titleNamesTarget() {
        #expect(EditorStrings.title(targetName: "Safari") == "Typing into Safari")
    }

    @Test func titleIsNeutralWithoutTarget() {
        #expect(EditorStrings.title(targetName: nil) == EditorStrings.neutralTitle)
        #expect(EditorStrings.title(targetName: "") == EditorStrings.neutralTitle)
    }

    @Test func hintsShowBothConditions() {
        #expect(EditorStrings.hints(TargetHints()) == [])
        #expect(EditorStrings.hints(TargetHints(willCopyToClipboard: true)) == ["Will copy to clipboard"])
        #expect(EditorStrings.hints(TargetHints(flattensNewlines: true)) == ["Line breaks become spaces"])
        #expect(
            EditorStrings.hints(TargetHints(willCopyToClipboard: true, flattensNewlines: true))
                == ["Will copy to clipboard", "Line breaks become spaces"]
        )
    }

    // MARK: HUD

    @Test(arguments: [
        InsertionFallbackReason.permissionMissing, .noEditableTarget, .targetChanged, .modifiersHeld,
    ])
    func copiedNoticeHasReason(_ reason: InsertionFallbackReason) {
        let content = NoticeContent(.copiedToClipboard(reason))
        #expect(content.title == "Copied — press ⌘V")
        #expect(content.subtitle?.isEmpty == false)
    }

    @Test func otherNotices() {
        #expect(NoticeContent(.clipboardReplaced).title == "Inserted — your clipboard now contains this text")
        #expect(NoticeContent(.secureFieldUnsupported).title == "Password fields aren't supported")
        #expect(NoticeContent(.hotkeyUnavailable(.default)).title == "Shortcut ⌃⌥⌘T unavailable")
    }

    // MARK: Status menu

    @Test func menuWithAllPermissions() {
        let items = StatusMenuModel.items(hotkey: .default, permissions: .allGranted, hotkeyUnavailable: nil)
        #expect(items == [
            .action(title: "Open Large Editor (⌃⌥⌘T)", action: .openEditor),
            .info(title: "Accessibility: Granted ✓"),
            .separator,
            .action(title: "Quit LargeText", action: .quit),
        ])
    }

    @Test func menuShowsHotkeyError() {
        let items = StatusMenuModel.items(hotkey: .default, permissions: .allGranted, hotkeyUnavailable: .default)
        #expect(items.contains(.info(title: "Shortcut ⌃⌥⌘T unavailable")))
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
