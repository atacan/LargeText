import AppKit
import LargeTextCore
import LargeTextPlatform
import LargeTextUI
import os

/// Owns the app lifecycle and the Kit-owned responsibilities (§3.9): activation policy, main menu, status
/// item, global hotkeys, the one-time accessibility request and the Settings window's coordinator.
///
/// It also keeps the editor, the reader and Settings apart (§4.8): the reader shortcut is ignored unless the
/// editor is idle, every way of opening the editor closes the reader first, and every way of opening Settings
/// closes both (Settings plan §3.5).
@MainActor
package final class AppController: NSObject, NSApplicationDelegate {
    private let environment: AppEnvironment
    private let launch: LaunchConfiguration

    package private(set) var coordinator: EditingSessionCoordinator?
    package private(set) var reader: ReadingSessionCoordinator?
    /// Both global shortcuts; created by `startSessions()`.
    package private(set) var shortcuts: HotkeyBindings?
    /// Shortcuts that couldn't be registered, editor first; the status menu lists them.
    package var hotkeyUnavailable: [KeyCombo] { shortcuts?.unavailable ?? [] }
    /// The Settings window's coordinator; created by `startSessions()`. Held strongly here: the closures it
    /// hands out hold it weakly.
    package private(set) var settings: SettingsCoordinator?
    private var statusItem: StatusItemController?
    private var inserter: (any TextInserting)?
    /// Set synchronously by `openEditorClosingReader()` and cleared once the editor has toggled, so a second
    /// press that arrives before the first task has even started is ignored.
    private var editorOpenTask: Task<Void, Never>?
    /// Set while `openSettings()` waits for the reader and the editor to close, so a second request is ignored.
    private var settingsOpenTask: Task<Void, Never>?
    /// The target of the main menu's app commands; `NSMenuItem.target` is weak.
    private var mainMenu: MainMenuBuilder?
    /// Only for the `reader-probe` scenario.
    private var probe: ReaderProbe?

    /// Stores only; no side effects.
    package init(environment: AppEnvironment, launch: LaunchConfiguration) {
        self.environment = environment
        self.launch = launch
        super.init()
    }

    // MARK: - NSApplicationDelegate

    package func applicationDidFinishLaunching(_ notification: Notification) {
        start()
    }

    package func applicationWillTerminate(_ notification: Notification) {
        stop()
    }

    // MARK: - Lifecycle

    package func start() {
        guard coordinator == nil else { return }
        Logger.kit.info(
            """
            Starting (scenario: \(self.launch.scenario?.rawValue ?? "none", privacy: .public), \
            presentOnLaunch: \(self.launch.presentOnLaunch, privacy: .public), \
            presentSettingsOnLaunch: \(self.launch.presentSettingsOnLaunch, privacy: .public), \
            presentReaderOnLaunch: \(self.launch.presentReaderOnLaunch?.rawValue ?? "none", privacy: .public))
            """
        )

        // 1. Activation policy (LSUIElement already makes us an accessory app; this is defensive).
        NSApplication.shared.setActivationPolicy(.accessory)
        //    The main menu, once: it only shows while Settings makes the app regular (Settings plan §3.3).
        let mainMenu = MainMenuBuilder(onOpenSettings: { [weak self] in self?.openSettings() })
        mainMenu.install()
        self.mainMenu = mainMenu

        // 2. Coordinators and global hotkeys. Assembly runs after any scenario mutation.
        startSessions()

        // 3. Status item, listing any shortcut that couldn't be registered. `shortcutsChanged()` keeps its
        //    combos current after a rebind.
        let preferences = environment.preferences
        let statusItem = StatusItemController(
            hotkey: preferences.hotkey,
            readerHotkey: preferences.readerHotkey,
            permissions: environment.permissions,
            onOpenEditor: { [weak self] in self?.openEditorClosingReader() },
            onReadTextUnderPointer: { [weak self] in self?.showReaderMenuHint() },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
        self.statusItem = statusItem
        shortcutsChanged()
        statusItem.install()

        // 4. Process-wide AX messaging timeout. Idempotent; while untrusted it fails and is retried by
        //    each later AX user (focus capture, reader reads).
        AXConfiguration.applyMessagingTimeoutIfNeeded()

        // 5. Ask for Accessibility once, outside any session; on the first launch, Settings opens first.
        requestAccessIfNeeded()

        // 6. The spike harness; the coordinators know nothing about it.
        if launch.scenario == .readerProbe {
            let probe = ReaderProbe(pointer: environment.pointer)
            probe.start()
            self.probe = probe
        }

        // 7. Present on launch.
        if launch.presentSettingsOnLaunch {
            openSettings()
        }
        if launch.presentOnLaunch {
            openEditorClosingReader()
        }
        if let state = launch.presentReaderOnLaunch {
            presentReader(state)
        }
    }

    package func stop() {
        // Put the user's clipboard back now rather than losing it if we quit right after a paste.
        (inserter as? PasteboardTextInserter)?.flushPendingRestore()
        inserter = nil
        settingsOpenTask?.cancel()
        settingsOpenTask = nil
        shortcuts?.onChange = nil
        shortcuts?.suspend()
        shortcuts = nil
        probe?.stop()
        probe = nil
        statusItem?.remove()
        statusItem = nil
        Logger.kit.info("Stopped")
    }

    // MARK: - Sessions

    /// Creates both coordinators and registers both shortcuts. A shortcut that can't be registered is listed
    /// in `hotkeyUnavailable` and reported with a notice; a reader that is off is simply not registered. No
    /// AppKit UI, so tests can drive it with spies.
    func startSessions() {
        let dependencies = environment.coreDependencies()
        coordinator = EditingSessionCoordinator(dependencies: dependencies)
        inserter = dependencies.inserter
        reader = ReadingSessionCoordinator(dependencies: environment.readerDependencies(timing: launch.readerTiming))

        let shortcuts = HotkeyBindings(
            hotkeys: environment.hotkeys,
            onEditor: { [weak self] in self?.openEditorClosingReader() },
            onReader: { [weak self] event in self?.readerHotkey(event) }
        )
        shortcuts.onChange = { [weak self] in self?.shortcutsChanged() }
        self.shortcuts = shortcuts

        let preferences = environment.preferences
        let failures = shortcuts.apply(editor: preferences.hotkey, reader: preferences.readerHotkey)
        for slot in ShortcutSlot.allCases {
            if let error = failures[slot] { reportUnavailable(error) }
        }

        // ⌘, in the editor or on the pinned card closes it, then comes here.
        coordinator?.onOpenSettings = { [weak self] in self?.openSettings() }
        reader?.onOpenSettings = { [weak self] in self?.openSettings() }
        let permissions = environment.permissions
        settings = SettingsCoordinator(dependencies: environment.settingsDependencies(
            shortcuts: shortcuts,
            context: launch.settingsContext,
            relaunch: { AppRelauncher.relaunch(onFailure: { permissions.openSystemSettings() }) }
        ))
    }

    /// Step 5 of `start()`. Asks for Accessibility when it is missing. On the first launch, Settings opens
    /// first, so its Accessibility row is there when the system prompt closes (Settings plan §3.6, D5); later
    /// launches only ask. With `--present-on-launch` the overlay would cover the prompt (§2.2), so both are
    /// left to the status menu. Every path marks the first launch as done.
    func requestAccessIfNeeded() {
        let preferences = environment.preferences
        let isFirstLaunch = !preferences.hasCompletedFirstLaunch
        preferences.hasCompletedFirstLaunch = true

        guard environment.permissions.current.setup != .granted else {
            (environment.permissions as? SystemPermissionsProvider)?.logDiagnostics()
            return
        }
        if launch.presentOnLaunch {
            Logger.kit.info("Access missing; prompt deferred because of --present-on-launch (use the status menu)")
            return
        }
        if isFirstLaunch {
            Logger.kit.info("First launch with access missing; opening Settings")
            openSettings()
        }
        Logger.kit.info("Accessibility or event posting missing; requesting access")
        environment.permissions.requestAccessibility()
    }

    /// The single path into Settings (Settings plan §3.2): the status menu, the main menu, ⌘, in the editor
    /// or on the pinned card, the first launch and `--present-settings-on-launch`. Opens at once when the
    /// reader and the editor are idle; otherwise closes the reader, then the editor (copying its text), then
    /// opens. Ignored while a previous call is still waiting.
    func openSettings() {
        guard let settings else {
            Logger.kit.debug("Settings request ignored: sessions haven't started yet")
            return
        }
        guard settingsOpenTask == nil else {
            Logger.kit.debug("Settings request ignored: Settings is already being opened")
            return
        }
        let reader = reader
        let coordinator = coordinator
        let editorOpening = editorOpenTask
        if reader?.isIdle != false, coordinator?.isIdle != false, editorOpening == nil {
            settings.show()
            return
        }
        settingsOpenTask = Task { [weak self] in
            await editorOpening?.value
            await reader?.close()
            await coordinator?.closeForSettings()
            settings.show()
            self?.settingsOpenTask = nil
        }
    }

    /// The single path into the editor: hotkey, status menu and present-on-launch (§4.8). Closes the reader
    /// first, awaiting its fade, then toggles the editor. Returns at once while a previous call is still in
    /// flight. When the reader is idle, `close()` doesn't suspend.
    func openEditorClosingReader() {
        guard editorOpenTask == nil, let coordinator else {
            Logger.kit.debug("Editor shortcut ignored: the editor is already being opened")
            return
        }
        unhideIfHidden()
        let reader = reader
        editorOpenTask = Task { [weak self] in
            await reader?.close()
            await coordinator.toggle()
            self?.editorOpenTask = nil
        }
    }

    /// Synchronous, so the reader decides tap vs. hold before the next event is delivered. Ignored while the
    /// editor is open, closing or being opened.
    private func readerHotkey(_ event: HotkeyEvent) {
        guard let reader, coordinator?.isIdle == true, editorOpenTask == nil else {
            Logger.kit.debug("Reader shortcut ignored while the editor is busy")
            return
        }
        if event.phase == .pressed, reader.isIdle {
            unhideIfHidden()
        }
        reader.hotkey(event)
    }

    /// ⌘H in the main menu hides the app while Settings is open, and a hidden app's panels don't show. The
    /// shortcuts bring it back first, without activating it.
    private func unhideIfHidden() {
        let app = NSApplication.shared
        guard app.isHidden else { return }
        Logger.kit.info("Unhiding the app for a shortcut")
        app.unhideWithoutActivation()
    }

    /// `--present-reader-on-launch`: a scripted press, stamped like a Carbon event, and for a tap an immediate
    /// release. Goes through the same guard as the real shortcut.
    private func presentReader(_ state: ReaderLaunchState) {
        let now = ProcessInfo.processInfo.systemUptime
        readerHotkey(HotkeyEvent(phase: .pressed, at: now))
        if state.releasesAtOnce {
            readerHotkey(HotkeyEvent(phase: .released, at: now))
        }
    }

    /// Launch-time only; `HotkeyBindings` has already logged it.
    private func reportUnavailable(_ error: HotkeyError) {
        guard case .unavailable(let combo) = error else { return }
        environment.notices.show(.hotkeyUnavailable(combo))
    }

    /// The menu shows the combos of the last `apply`, which may not be saved yet (a rebind saves only
    /// once it registers). The menu itself rebuilds when it opens.
    private func shortcutsChanged() {
        guard let statusItem, let shortcuts else { return }
        if let editor = shortcuts.editorCombo {
            statusItem.hotkey = editor
        }
        statusItem.readerHotkey = shortcuts.readerCombo
        statusItem.hotkeyUnavailable = shortcuts.unavailable
    }

    /// The status menu's "Read Text Under Pointer": the pointer is on the menu, so reading would be
    /// pointless. Shows how to use the shortcut instead, read now so a rebind is reflected.
    private func showReaderMenuHint() {
        guard let combo = environment.preferences.readerHotkey else {
            Logger.kit.debug("Reader menu hint skipped: the reader is off")
            return
        }
        environment.notices.show(.readerMenuHint(combo))
    }
}
