import AppKit
import LargeTextCore
import LargeTextPlatform
import LargeTextUI
import os

/// Owns the app lifecycle and the Kit-owned responsibilities (§3.9): activation policy, status item,
/// global hotkeys and the one-time accessibility request. Never touches `NSApp.mainMenu`.
///
/// It also keeps the editor and the reader apart (§4.8): the reader shortcut is ignored unless the editor is
/// idle, and every way of opening the editor closes the reader first.
@MainActor
package final class AppController: NSObject, NSApplicationDelegate {
    private let environment: AppEnvironment
    private let launch: LaunchConfiguration

    package private(set) var coordinator: EditingSessionCoordinator?
    package private(set) var reader: ReadingSessionCoordinator?
    /// Shortcuts that couldn't be registered, in order; the status menu lists them.
    package private(set) var hotkeyUnavailable: [KeyCombo] = []
    private var statusItem: StatusItemController?
    private var hotkeyRegistration: (any HotkeyRegistration)?
    private var readerHotkeyRegistration: (any HotkeyRegistration)?
    private var inserter: (any TextInserting)?
    /// Set synchronously by `openEditorClosingReader()` and cleared once the editor has toggled, so a second
    /// press that arrives before the first task has even started is ignored.
    private var editorOpenTask: Task<Void, Never>?
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
            presentReaderOnLaunch: \(self.launch.presentReaderOnLaunch?.rawValue ?? "none", privacy: .public))
            """
        )

        // 1. Activation policy (LSUIElement already makes us an accessory app; this is defensive).
        NSApplication.shared.setActivationPolicy(.accessory)

        // 2. Coordinators and global hotkeys. Assembly runs after any scenario mutation.
        startSessions()

        // 3. Status item, listing any shortcut that couldn't be registered.
        let preferences = environment.preferences
        let notices = environment.notices
        let readerHotkey = preferences.readerHotkey
        let statusItem = StatusItemController(
            hotkey: preferences.hotkey,
            readerHotkey: readerHotkey,
            permissions: environment.permissions,
            onOpenEditor: { [weak self] in self?.openEditorClosingReader() },
            // The pointer is on the menu, so reading would be pointless: show how to use the shortcut instead.
            onReadTextUnderPointer: { notices.show(.readerMenuHint(readerHotkey)) }
        )
        statusItem.hotkeyUnavailable = hotkeyUnavailable
        statusItem.install()
        self.statusItem = statusItem

        // 4. Process-wide AX messaging timeout. Idempotent; while untrusted it fails and is retried by
        //    each later AX user (focus capture, reader reads).
        AXConfiguration.applyMessagingTimeoutIfNeeded()

        // 5. Ask for Accessibility once, outside any session. With --present-on-launch the overlay
        //    would cover the system prompt (§2.2), so the request is left to the status menu.
        let permissions = environment.permissions.current
        if permissions.accessibility == .denied || permissions.eventPosting == .denied {
            if launch.presentOnLaunch {
                Logger.kit.info("Access missing; prompt deferred because of --present-on-launch (use the status menu)")
            } else {
                Logger.kit.info("Accessibility or event posting missing; requesting access")
                environment.permissions.requestAccessibility()
            }
        } else if let system = environment.permissions as? SystemPermissionsProvider {
            system.logDiagnostics()
        }

        // 6. The spike harness; the coordinators know nothing about it.
        if launch.scenario == .readerProbe {
            let probe = ReaderProbe(pointer: environment.pointer)
            probe.start()
            self.probe = probe
        }

        // 7. Present on launch.
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
        hotkeyRegistration?.unregister()
        hotkeyRegistration = nil
        readerHotkeyRegistration?.unregister()
        readerHotkeyRegistration = nil
        probe?.stop()
        probe = nil
        statusItem?.remove()
        statusItem = nil
        Logger.kit.info("Stopped")
    }

    // MARK: - Sessions

    /// Creates both coordinators and registers both shortcuts. A shortcut that can't be registered is added
    /// to `hotkeyUnavailable` and reported with a notice. No AppKit UI, so tests can drive it with spies.
    func startSessions() {
        let dependencies = environment.coreDependencies()
        coordinator = EditingSessionCoordinator(dependencies: dependencies)
        inserter = dependencies.inserter
        reader = ReadingSessionCoordinator(dependencies: environment.readerDependencies(timing: launch.readerTiming))

        let editorHotkey = environment.preferences.hotkey
        do {
            hotkeyRegistration = try environment.hotkeys.registerPressOnly(editorHotkey) { [weak self] in
                self?.openEditorClosingReader()
            }
        } catch {
            reportUnavailable(error)
        }

        // An equal combo would steal the editor's shortcut: the reader isn't registered then (§4.10).
        do {
            let readerHotkey = try HotkeyConflicts.validate(editor: editorHotkey, reader: environment.preferences.readerHotkey).get()
            readerHotkeyRegistration = try environment.hotkeys.register(readerHotkey) { [weak self] event in
                self?.readerHotkey(event)
            }
        } catch {
            reportUnavailable(error)
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
        reader.hotkey(event)
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

    private func reportUnavailable(_ error: HotkeyError) {
        Logger.kit.error("Hotkey unavailable: \(String(describing: error), privacy: .public)")
        guard case .unavailable(let combo) = error else { return }
        hotkeyUnavailable.append(combo)
        environment.notices.show(.hotkeyUnavailable(combo))
    }
}
