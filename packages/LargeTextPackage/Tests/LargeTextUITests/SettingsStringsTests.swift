import LargeTextCore
import Testing
@testable import LargeTextUI

@Suite("SettingsStrings")
struct SettingsStringsTests {
    @Test func combos() {
        #expect(SettingsStrings.combo(.default) == "⌃⌥⌘T")
        #expect(SettingsStrings.combo(.readerDefault) == "⌃⌥⌘R")
        #expect(SettingsStrings.combo(nil) == "Off")
    }

    @Test func shortcutTitlesMatchTheStatusMenu() {
        #expect(SettingsStrings.shortcutTitle(.editor) == "Open Large Editor")
        #expect(SettingsStrings.shortcutTitle(.reader) == "Read Text Under Pointer")
    }

    @Test func everyProblemHasWording() {
        let problems: [ShortcutProblem] = [
            .needsModifier, .optionOnlyRefused, .reservedBySystem, .sameAsOther(.editor), .sameAsOther(.reader), .unavailable,
        ]
        let texts = problems.map(SettingsStrings.problem)
        #expect(texts.allSatisfy { !$0.isEmpty && $0.hasSuffix(".") })
        #expect(Set(texts).count == problems.count)
    }

    @Test func sameAsOtherNamesTheOtherShortcut() {
        #expect(SettingsStrings.problem(.sameAsOther(.editor)) == "Already used for Open Large Editor.")
        #expect(SettingsStrings.problem(.sameAsOther(.reader)) == "Already used for Read Text Under Pointer.")
    }

    @Test func recordingShowsThePromptThenTheHeldModifiers() {
        #expect(SettingsStrings.recording([]) == "Type Shortcut")
        #expect(SettingsStrings.recording([.control, .option]) == "⌃⌥…")
        #expect(SettingsStrings.recording([.command, .shift, .control, .option]) == "⌃⌥⇧⌘…")
    }

    @Test func values() {
        #expect(SettingsStrings.fontSize(FontSize(points: 64)) == "64 pt")
        #expect(SettingsStrings.fontSize(FontSize(points: 71.6)) == "72 pt")
        #expect(SettingsStrings.milliseconds(300) == "300 ms")
        #expect(ReadGranularity.allCases.map(SettingsStrings.unit) == ["Sentence", "Line", "Paragraph"])
    }

    @Test func permissionRow() {
        #expect(SettingsStrings.permissionStatus(.granted) == "Granted ✓")
        #expect(SettingsStrings.permissionStatus(.needsRelaunch) == "Relaunch to finish setup")
        #expect(SettingsStrings.permissionStatus(.needsGrant) == "Not granted")
        #expect(SettingsStrings.permissionFootnote(.granted) == nil)
        #expect(SettingsStrings.permissionFootnote(.needsGrant) != nil)
        #expect(SettingsStrings.permissionFootnote(.needsRelaunch) != nil)
        // The same wording as the status menu's item (D6).
        #expect(StatusMenuModel.permissionItem(.allDenied) == .action(title: SettingsStrings.grantAccess, action: .grantAccess))
    }

    @Test func loginItemRow() {
        #expect(SettingsStrings.launchAtLogin == "Launch at login")
        #expect(SettingsStrings.loginItemNote(.enabled) == nil)
        #expect(SettingsStrings.loginItemNote(.notRegistered) == nil)
        #expect(SettingsStrings.loginItemNote(.requiresApproval)?.contains("Login Items") == true)
        #expect(SettingsStrings.loginItemNote(.notFound)?.contains("Applications") == true)
        #expect(SettingsStrings.loginItemError(.notPermitted).contains("Login Items"))
        #expect(SettingsStrings.loginItemError(.failed(code: 3)) == "Launch at login couldn't be changed (error 3).")
    }

    @Test func theLoginItemsButtonShowsWhenThereIsSomethingToDoThere() {
        #expect(SettingsStrings.showsOpenLoginItems(status: .requiresApproval, error: nil))
        #expect(SettingsStrings.showsOpenLoginItems(status: .notRegistered, error: .notPermitted))
        #expect(!SettingsStrings.showsOpenLoginItems(status: .enabled, error: nil))
        #expect(!SettingsStrings.showsOpenLoginItems(status: .notRegistered, error: .failed(code: 2)))
        #expect(!SettingsStrings.showsOpenLoginItems(status: .notFound, error: nil))
    }

    @Test func overrideNotesNameTheArgument() {
        #expect(SettingsStrings.overrideNote(.readerHoldThreshold) == "Set by --reader-hold-threshold for this run; not saved.")
        #expect(SettingsStrings.overrideNote(.followingUnit) == "Set by --following-unit for this run; not saved.")
        #expect(SettingsStrings.overrideNote(.fontSize) == "Set on the command line for this run; not saved.")
    }

    @Test func scenarioBanner() {
        #expect(SettingsStrings.scenarioBanner("reader-stub") == "Scenario 'reader-stub': changes are kept in memory only.")
    }

    @MainActor
    @Test func holdThresholdSliderMatchesReaderDefaults() {
        #expect(SettingsViewModel.holdThresholdRange == 150...800)
        #expect(SettingsViewModel.holdThresholdStep == 25)
        #expect(SettingsViewModel.milliseconds(.milliseconds(300)) == 300)
        #expect(SettingsViewModel.milliseconds(.seconds(1.5)) == 1_500)
    }
}
