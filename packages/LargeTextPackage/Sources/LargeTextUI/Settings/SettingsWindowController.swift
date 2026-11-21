import AppKit
import LargeTextCore
import os
import SwiftUI

/// The live `SettingsPresenting` (Settings plan §3.1, §3.3): a regular, reused `NSWindow` hosting
/// `SettingsView`.
///
/// While it is shown the app is a regular app, with a Dock icon, a ⌘Tab entry and the main menu
/// (`SettingsActivation`). Closing it, with ⌘W, ⎋ or the close button, makes the app an accessory again and
/// hands focus back to the app that was frontmost before.
///
/// Window events become intents: `.becameKey`, `.resignedKey`, then `.closed` once `isVisible` is false.
@MainActor
package final class SettingsWindowController: NSObject, SettingsPresenting, NSWindowDelegate {
    private let activation: any SettingsActivation
    private let frameAutosaveName: String?

    private(set) var window: NSWindow?
    private(set) var model: SettingsViewModel?
    /// Between `show` and the window closing. Not affected by minimizing, so the permission refresh keeps
    /// running for a minimized window that comes back.
    private var isShown = false

    /// - Parameters:
    ///   - activation: the activation-policy switch; tests pass one that leaves the process alone.
    ///   - frameAutosaveName: where the window frame is remembered; `nil` in tests.
    package init(
        activation: any SettingsActivation = AppActivationSwitch(),
        frameAutosaveName: String? = "LargeText.Settings"
    ) {
        self.activation = activation
        self.frameAutosaveName = frameAutosaveName
        super.init()
    }

    // MARK: - SettingsPresenting

    package var isVisible: Bool { isShown }

    package func show(_ state: SettingsState, intents: @escaping @MainActor (SettingsIntent) -> Void) {
        let (window, model) = makeWindowIfNeeded(state)
        model.state = state
        model.intents = intents
        isShown = true
        // On every show, not only the first: a repeated "Settings…" must bring the window back from behind
        // another app, or after ⌘H.
        activation.activateForSettings()
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        // Cooperative activation may not make the app active at once; the window still comes to the front.
        window.orderFrontRegardless()
        Logger.ui.info("Settings shown")
    }

    package func update(_ state: SettingsState) {
        guard isShown, let model else { return }
        model.state = state
    }

    // MARK: - NSWindowDelegate

    package func windowDidBecomeKey(_ notification: Notification) {
        send(.becameKey)
    }

    package func windowDidResignKey(_ notification: Notification) {
        send(.resignedKey)
    }

    package func windowWillClose(_ notification: Notification) {
        guard isShown else { return }
        isShown = false
        send(.closed)
        activation.restoreAfterSettings()
        Logger.ui.info("Settings closed")
    }

    // MARK: - Private

    private func send(_ intent: SettingsIntent) {
        model?.send(intent)
    }

    private func makeWindowIfNeeded(_ state: SettingsState) -> (NSWindow, SettingsViewModel) {
        if let window, let model { return (window, model) }
        let model = SettingsViewModel(state: state)
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        // The window keeps its (autosaved) size; the form scrolls inside it.
        hosting.sizingOptions = [.minSize]

        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.title = SettingsStrings.windowTitle
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 520, height: 680))
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.tabbingMode = .disallowed
        window.delegate = self
        window.center()
        if let frameAutosaveName {
            // After `center()`, so a remembered frame wins.
            window.setFrameAutosaveName(frameAutosaveName)
        }
        self.window = window
        self.model = model
        return (window, model)
    }
}

/// ⎋ closes the window, like ⌘W (Settings plan §3.3).
private final class SettingsWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}
