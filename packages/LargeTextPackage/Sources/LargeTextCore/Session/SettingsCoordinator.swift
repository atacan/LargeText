import Foundation
import os

/// Owns the Settings window (Settings plan §3.8). It is the only writer from the UI: every intent writes
/// `PreferencesStore` or calls a port, then the whole `SettingsState` is rebuilt from the store and the ports
/// and sent to the presenter. Font sizes, hold threshold, units and clipboard restore need nothing more: the
/// session coordinators read them when a session starts.
///
/// The shortcuts are the exception. A recorded combo passes `ShortcutRules`, then is tried with
/// `ShortcutBinding.apply`; it is saved only when that registration succeeds, otherwise the saved combos are
/// applied again. Recording suspends both shortcuts, and anything that ends a recording without a combo
/// (⎋, the window resigning key or closing) applies the saved ones again.
@MainActor
package final class SettingsCoordinator {
    /// Rebuilt on every read from the store, the ports and the window's transient state.
    package var state: SettingsState { makeState() }
    /// Between `show()` and `.closed`.
    package private(set) var isOpen = false
    /// Whether the permission refresh is scheduled.
    package var isRefreshing: Bool { refresh != nil }

    private let dependencies: SettingsDependencies
    /// The slot whose recorder is recording, if any; only one at a time.
    private var recording: ShortcutSlot?
    /// Both shortcuts are unregistered by `suspend()` and must be applied again.
    private var isSuspended = false
    private var problems: [ShortcutSlot: ShortcutProblem] = [:]
    private var loginItemError: LoginItemError?
    /// The state last sent, so the refresh only sends changes.
    private var lastSent: SettingsState?
    private var refresh: Task<Void, Never>?

    package init(dependencies: SettingsDependencies) {
        self.dependencies = dependencies
    }

    /// Opens the window, or brings it to the front. Problems from an earlier opening are cleared.
    package func show() {
        if !isOpen {
            problems = [:]
            loginItemError = nil
        }
        isOpen = true
        let state = makeState()
        lastSent = state
        dependencies.presenter.show(state) { [weak self] intent in
            self?.handle(intent)
        }
        startRefresh()
    }

    package func handle(_ intent: SettingsIntent) {
        let preferences = dependencies.preferences
        switch intent {
        case .beginRecording(let slot):
            beginRecording(slot)
        case .cancelRecording, .resignedKey:
            endRecording()
        case .record(let slot, let combo):
            recording = nil
            rebind(slot, to: combo)
        case .resetShortcut(let slot):
            recording = nil
            rebind(slot, to: slot.defaultCombo)
        case .turnOffReader:
            turnOffReader()
        case .setEditorFontSize(let size):
            preferences.fontSize = FontSizePolicy.clamp(size)
        case .setReaderFontSize(let size):
            preferences.readerFontSize = FontSizePolicy.clamp(size)
        case .setHoldThreshold(let threshold):
            preferences.readerHoldThreshold = ReaderDefaults.clampHoldThreshold(threshold)
        case .setFollowingUnit(let unit):
            preferences.followingUnit = unit
        case .setPinnedUnit(let unit):
            preferences.pinnedUnit = unit
        case .setRestoresClipboard(let restores):
            setRestoresClipboard(restores)
        case .setLaunchAtLogin(let enabled):
            setLaunchAtLogin(enabled)
        case .grantAccess:
            // D6: the request adds the app to the Accessibility list (and prompts); the pane shows it there.
            dependencies.permissions.requestAccessibility()
            dependencies.permissions.openSystemSettings()
        case .relaunch:
            dependencies.relaunch()
        case .openLoginItemsSettings:
            dependencies.loginItem?.openSystemSettings()
        case .resetAll:
            resetAll()
        case .becameKey:
            break    // The publish below re-reads the store and the permissions.
        case .closed:
            close()
            return
        }
        publish()
    }

    // MARK: - Shortcuts

    private func beginRecording(_ slot: ShortcutSlot) {
        recording = slot
        problems[slot] = nil
        guard !isSuspended else { return }
        dependencies.shortcuts.suspend()
        isSuspended = true
    }

    /// Ends any recording without a new combo: the saved combos are registered again.
    private func endRecording() {
        recording = nil
        resume()
    }

    /// Checks `combo`, tries it, and saves it only when its registration succeeded. A refused combo leaves the
    /// saved ones registered.
    private func rebind(_ slot: ShortcutSlot, to combo: KeyCombo) {
        let saved = savedCombos
        problems[slot] = nil
        if let problem = ShortcutRules.validate(combo, for: slot, other: saved[slot.other]) {
            Logger.core.info("Settings: \(String(describing: slot), privacy: .public) shortcut refused (\(String(describing: problem), privacy: .public))")
            problems[slot] = problem
            resume()
            return
        }
        let proposed = saved.replacing(slot, with: combo)
        guard apply(proposed)[slot] == nil else {
            Logger.core.error("Settings: \(String(describing: slot), privacy: .public) shortcut unavailable; restoring the saved ones")
            apply(saved)
            problems[slot] = .unavailable
            return
        }
        switch slot {
        case .editor: dependencies.preferences.hotkey = combo
        case .reader: dependencies.preferences.readerHotkey = combo
        }
        Logger.core.info("Settings: \(String(describing: slot), privacy: .public) shortcut saved")
    }

    /// D1. Saved first: the reader is then off even if the app stops before the registration below.
    private func turnOffReader() {
        recording = nil
        problems[.reader] = nil
        dependencies.preferences.readerHotkey = nil
        apply(savedCombos)
        Logger.core.info("Settings: reader shortcut turned off")
    }

    private func resume() {
        guard isSuspended else { return }
        apply(savedCombos)
    }

    @discardableResult
    private func apply(_ combos: Combos) -> [ShortcutSlot: HotkeyError] {
        isSuspended = false
        return dependencies.shortcuts.apply(editor: combos.editor, reader: combos.reader)
    }

    private var savedCombos: Combos {
        Combos(editor: dependencies.preferences.hotkey, reader: dependencies.preferences.readerHotkey)
    }

    // MARK: - Other settings

    /// A custom `restore(maxBytes:)` from `defaults write` is kept until the toggle is turned off; turning it
    /// on again writes the default.
    private func setRestoresClipboard(_ restores: Bool) {
        let preferences = dependencies.preferences
        if restores {
            if case .restore = preferences.clipboardRestore { return }
            preferences.clipboardRestore = .default
        } else {
            preferences.clipboardRestore = .none
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard let loginItem = dependencies.loginItem else { return }
        do {
            try loginItem.setEnabled(enabled)
            loginItemError = nil
        } catch {
            Logger.core.error("Settings: launch at login \(enabled ? "enable" : "disable", privacy: .public) failed: \(String(describing: error), privacy: .public)")
            loginItemError = error
        }
    }

    /// Every default, then one registration of the default shortcuts. Launch at login is system state, and
    /// `hasCompletedFirstLaunch` isn't a setting; both are left alone.
    private func resetAll() {
        recording = nil
        problems = [:]
        let preferences = dependencies.preferences
        preferences.hotkey = ShortcutSlot.editor.defaultCombo
        preferences.readerHotkey = ShortcutSlot.reader.defaultCombo
        preferences.fontSize = FontSizePolicy.default
        preferences.readerFontSize = FontSizePolicy.default
        preferences.readerHoldThreshold = ReaderDefaults.holdThreshold
        preferences.followingUnit = ReaderDefaults.followingUnit
        preferences.pinnedUnit = ReaderDefaults.pinnedUnit
        preferences.clipboardRestore = .default
        apply(savedCombos)
        Logger.core.info("Settings: reset to defaults")
    }

    // MARK: - Window

    private func close() {
        endRecording()
        refresh?.cancel()
        refresh = nil
        isOpen = false
        lastSent = nil
    }

    /// Re-reads everything every `permissionRefreshInterval` while the window is visible: Accessibility changes
    /// outside the app, and so may a size (⌘± in a session) or the login item's approval.
    private func startRefresh() {
        guard refresh == nil else { return }
        let sleeper = dependencies.sleeper
        let interval = dependencies.permissionRefreshInterval
        refresh = Task { [weak self] in
            while true {
                do { try await sleeper.sleep(for: interval) } catch { return }
                guard let self, !Task.isCancelled else { return }
                guard self.isOpen, self.dependencies.presenter.isVisible else {
                    self.refresh = nil
                    return
                }
                self.publishIfChanged()
            }
        }
    }

    private func publish() {
        guard isOpen else { return }
        let state = makeState()
        lastSent = state
        dependencies.presenter.update(state)
    }

    private func publishIfChanged() {
        guard makeState() != lastSent else { return }
        publish()
    }

    private func makeState() -> SettingsState {
        let preferences = dependencies.preferences
        let unregistered = dependencies.shortcuts.unavailableSlots
        func shortcut(_ slot: ShortcutSlot, _ combo: KeyCombo?) -> SettingsState.Shortcut {
            SettingsState.Shortcut(
                combo: combo,
                isRecording: recording == slot,
                problem: problems[slot],
                isRegistered: combo != nil && !unregistered.contains(slot)
            )
        }
        return SettingsState(
            editorShortcut: shortcut(.editor, preferences.hotkey),
            readerShortcut: shortcut(.reader, preferences.readerHotkey),
            editorFontSize: FontSizePolicy.clamp(preferences.fontSize),
            readerFontSize: FontSizePolicy.clamp(preferences.readerFontSize),
            holdThreshold: preferences.readerHoldThreshold,
            followingUnit: preferences.followingUnit,
            pinnedUnit: preferences.pinnedUnit,
            restoresClipboard: preferences.clipboardRestore != .none,
            permission: dependencies.permissions.current.setup,
            loginItem: dependencies.loginItem?.status,
            loginItemError: loginItemError,
            context: dependencies.context
        )
    }
}

/// The pair `ShortcutBinding.apply` takes.
private struct Combos {
    var editor: KeyCombo
    var reader: KeyCombo?

    subscript(slot: ShortcutSlot) -> KeyCombo? {
        switch slot {
        case .editor: editor
        case .reader: reader
        }
    }

    func replacing(_ slot: ShortcutSlot, with combo: KeyCombo) -> Combos {
        var combos = self
        switch slot {
        case .editor: combos.editor = combo
        case .reader: combos.reader = combo
        }
        return combos
    }
}
