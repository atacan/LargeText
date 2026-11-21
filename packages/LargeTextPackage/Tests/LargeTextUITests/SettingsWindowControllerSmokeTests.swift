import AppKit
import LargeTextCore
import SwiftUI
import Testing
@testable import LargeTextUI

/// Creates a real window with a spy activation switch, so the test process's activation policy and the
/// frontmost app are left alone, and no frame autosave name, so nothing is written to the defaults.
@MainActor
@Suite("SettingsWindowController smoke", .enabled(if: !NSScreen.screens.isEmpty))
struct SettingsWindowControllerSmokeTests {
    @MainActor
    final class SpyActivation: SettingsActivation {
        enum Call: Equatable { case activate, restore }
        private(set) var calls: [Call] = []

        func activateForSettings() { calls.append(.activate) }
        func restoreAfterSettings() { calls.append(.restore) }
    }

    let activation = SpyActivation()

    private func makeController() -> SettingsWindowController {
        _ = NSApplication.shared
        return SettingsWindowController(activation: activation, frameAutosaveName: nil)
    }

    private func state(
        permission: PermissionSetup = .granted,
        reader: KeyCombo? = .readerDefault,
        loginItem: LoginItemStatus? = nil,
        loginItemError: LoginItemError? = nil
    ) -> SettingsState {
        SettingsState(
            editorShortcut: SettingsState.Shortcut(combo: .default, isRegistered: true),
            readerShortcut: SettingsState.Shortcut(combo: reader, isRegistered: reader != nil),
            editorFontSize: FontSizePolicy.default,
            readerFontSize: FontSizePolicy.default,
            holdThreshold: ReaderDefaults.holdThreshold,
            followingUnit: ReaderDefaults.followingUnit,
            pinnedUnit: ReaderDefaults.pinnedUnit,
            restoresClipboard: true,
            permission: permission,
            loginItem: loginItem,
            loginItemError: loginItemError,
            context: SettingsContext(scenarioName: "first-launch", launchOverrides: [.readerHoldThreshold])
        )
    }

    @Test func showCreatesTheWindowAndSwitchesToARegularApp() throws {
        let controller = makeController()

        controller.show(state()) { _ in }
        let window = try #require(controller.window)
        defer { window.close() }

        #expect(window.isVisible)
        #expect(controller.isVisible)
        #expect(window.title == "LargeText Settings")
        #expect(window.styleMask.contains(.closable))
        #expect(window.styleMask.contains(.titled))
        #expect(!(window is NSPanel))
        #expect(!window.isReleasedWhenClosed)
        #expect(!window.hidesOnDeactivate)
        #expect(window.collectionBehavior.contains(.moveToActiveSpace))
        #expect(window.contentViewController is NSHostingController<SettingsView>)
        #expect(activation.calls == [.activate])
        #expect(controller.model?.state == state())
    }

    @Test func theFormLaysOutInEveryPermissionState() throws {
        let controller = makeController()
        for permission in [PermissionSetup.granted, .needsGrant, .needsRelaunch] {
            controller.show(state(permission: permission, reader: nil)) { _ in }
            let view = try #require(controller.window?.contentView)
            view.layoutSubtreeIfNeeded()
            #expect(view.frame.width >= 460)
        }
        controller.window?.close()
    }

    @Test func theFormLaysOutInEveryLoginItemState() throws {
        let controller = makeController()
        let states: [(LoginItemStatus?, LoginItemError?)] = [
            (nil, nil), (.notRegistered, nil), (.enabled, nil), (.requiresApproval, nil), (.notFound, nil),
            (.notRegistered, .notPermitted), (.enabled, .failed(code: 2)),
        ]
        for (status, error) in states {
            controller.show(state(loginItem: status, loginItemError: error)) { _ in }
            let view = try #require(controller.window?.contentView)
            view.layoutSubtreeIfNeeded()
            #expect(view.frame.width >= 460)
            #expect(controller.model?.state.loginItem == status)
        }
        controller.window?.close()
    }

    @Test func updateReplacesTheStateOnlyWhileShown() throws {
        let controller = makeController()
        controller.show(state()) { _ in }
        let window = try #require(controller.window)

        controller.update(state(permission: .needsGrant))
        #expect(controller.model?.state.permission == .needsGrant)

        window.close()
        controller.update(state(permission: .needsRelaunch))
        #expect(controller.model?.state.permission == .needsGrant)
    }

    @Test func escapeClosesSendsClosedWhenNoLongerVisibleAndRestoresTheApp() throws {
        let controller = makeController()
        var received: [SettingsIntent] = []
        var visibleWhenClosed: Bool?
        controller.show(state()) { intent in
            received.append(intent)
            if intent == .closed { visibleWhenClosed = controller.isVisible }
        }
        let window = try #require(controller.window)

        window.cancelOperation(nil)

        #expect(!window.isVisible)
        #expect(!controller.isVisible)
        #expect(received.last == .closed)
        #expect(received.filter { $0 == .closed }.count == 1)
        #expect(visibleWhenClosed == false)
        #expect(activation.calls == [.activate, .restore])
    }

    /// Every show activates (bringing an open window back from behind another app); every close restores.
    @Test func showingAgainReusesTheWindowAndActivatesEachTime() throws {
        let controller = makeController()
        controller.show(state()) { _ in }
        let window = try #require(controller.window)

        controller.show(state(permission: .needsGrant)) { _ in }
        #expect(activation.calls == [.activate, .activate])
        #expect(controller.model?.state.permission == .needsGrant)

        window.performClose(nil)
        controller.show(state()) { _ in }
        defer { window.close() }

        #expect(controller.window === window)
        #expect(window.isVisible)
        #expect(activation.calls == [.activate, .activate, .restore, .activate])
    }

    @Test func keyChangesBecomeIntentsForTheLatestShow() throws {
        let controller = makeController()
        var first: [SettingsIntent] = []
        var second: [SettingsIntent] = []
        controller.show(state()) { first.append($0) }
        controller.show(state()) { second.append($0) }
        let window = try #require(controller.window)
        defer { window.close() }
        first.removeAll()
        second.removeAll()

        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: window))

        #expect(first.isEmpty)
        #expect(second == [.becameKey, .resignedKey])
    }

    // MARK: - Recorders inside the hosted form

    private func recorders(in view: NSView) -> [ShortcutRecorderView] {
        view.subviews.flatMap { subview in
            (subview as? ShortcutRecorderView).map { [$0] } ?? recorders(in: subview)
        }
    }

    private func key(_ window: NSWindow, _ keyCode: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    /// The real path through `NSHostingView`: both recorders are in the form, a click-free start (Space) sends
    /// `.beginRecording`, and a ⌘ combo sent to the window as a key equivalent reaches the recorder.
    @Test func recordersInTheFormReceiveKeyEquivalentsFromTheWindow() throws {
        let controller = makeController()
        var received: [SettingsIntent] = []
        controller.show(state()) { received.append($0) }
        let window = try #require(controller.window)
        defer { window.close() }
        let content = try #require(window.contentView)
        content.layoutSubtreeIfNeeded()
        let found = recorders(in: content)
        #expect(found.map(\.displayedText) == ["⌃⌥⌘T", "⌃⌥⌘R"])
        let editor = try #require(found.first)
        #expect(editor.accessibilityLabel() == "Open Large Editor")

        #expect(window.makeFirstResponder(editor))
        received.removeAll()
        window.sendEvent(key(window, ANSIKeyCode.space, " "))
        #expect(received == [.beginRecording(.editor)])
        #expect(editor.isRecording)

        #expect(window.performKeyEquivalent(with: key(window, 0x28, "k", [.command, .shift])))
        #expect(received == [.beginRecording(.editor), .record(.editor, KeyCombo(keyCode: 0x28, modifiers: [.command, .shift]))])
    }

    /// ⎋ on a focused, idle recorder still closes the window; while recording it only cancels.
    @Test func escapeOnARecorderCancelsWhileRecordingAndClosesOtherwise() throws {
        let controller = makeController()
        var received: [SettingsIntent] = []
        controller.show(state()) { received.append($0) }
        let window = try #require(controller.window)
        defer { window.close() }
        let content = try #require(window.contentView)
        content.layoutSubtreeIfNeeded()
        let reader = try #require(recorders(in: content).last)
        #expect(window.makeFirstResponder(reader))
        received.removeAll()

        window.sendEvent(key(window, ANSIKeyCode.space, " "))
        window.sendEvent(key(window, ANSIKeyCode.escape, "\u{1B}"))
        #expect(received == [.beginRecording(.reader), .cancelRecording])
        #expect(window.isVisible)

        window.sendEvent(key(window, ANSIKeyCode.escape, "\u{1B}"))
        #expect(!window.isVisible)
        #expect(received.last == .closed)
    }
}
