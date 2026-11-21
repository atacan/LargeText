import LargeTextCore
import SwiftUI

// Fast visual loop for the Settings window (select the package scheme in Xcode). Intents go nowhere, so the
// controls snap back: only `SettingsCoordinator` changes the state.

@MainActor
private func settingsPreview(_ change: (inout SettingsState) -> Void = { _ in }) -> some View {
    var state = SettingsState(
        editorShortcut: SettingsState.Shortcut(combo: .default, isRegistered: true),
        readerShortcut: SettingsState.Shortcut(combo: .readerDefault, isRegistered: true),
        editorFontSize: FontSizePolicy.default,
        readerFontSize: FontSize(points: 88),
        holdThreshold: ReaderDefaults.holdThreshold,
        followingUnit: ReaderDefaults.followingUnit,
        pinnedUnit: ReaderDefaults.pinnedUnit,
        restoresClipboard: true,
        permission: .granted,
        loginItem: .notRegistered,
        context: .standard
    )
    change(&state)
    return SettingsView(model: SettingsViewModel(state: state))
        .frame(width: 520, height: 680)
}

#Preview("Default") {
    settingsPreview()
}

#Preview("Accessibility denied") {
    settingsPreview { $0.permission = .needsGrant }
}

#Preview("Needs relaunch") {
    settingsPreview { $0.permission = .needsRelaunch }
}

#Preview("Recording") {
    settingsPreview { $0.editorShortcut.isRecording = true }
}

#Preview("Conflict") {
    settingsPreview { $0.readerShortcut.problem = .sameAsOther(.editor) }
}

#Preview("Unavailable") {
    settingsPreview {
        $0.editorShortcut.problem = .unavailable
        $0.readerShortcut.isRegistered = false
    }
}

#Preview("Reader off") {
    settingsPreview { $0.readerShortcut = SettingsState.Shortcut(combo: nil, isRegistered: false) }
}

#Preview("Launch override") {
    settingsPreview {
        $0.holdThreshold = .milliseconds(450)
        $0.context = SettingsContext(scenarioName: "reader-stub", launchOverrides: [.readerHoldThreshold, .followingUnit])
    }
}

#Preview("Login item requires approval") {
    settingsPreview { $0.loginItem = .requiresApproval }
}

#Preview("Login item not permitted") {
    settingsPreview { $0.loginItemError = .notPermitted }
}
