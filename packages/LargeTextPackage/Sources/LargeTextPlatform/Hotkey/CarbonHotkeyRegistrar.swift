import Carbon.HIToolbox
import LargeTextCore
import os

/// Global hotkeys via Carbon `RegisterEventHotKey` (needs no TCC permission, §2.1).
///
/// One application-level handler for `kEventHotKeyPressed` and `kEventHotKeyReleased` is installed lazily
/// on the first `register` and removed again when the last registration is unregistered. While installed,
/// the Carbon handler holds a retained reference to the registrar, so the registrar cannot be deallocated
/// under Carbon.
@MainActor
package final class CarbonHotkeyRegistrar: HotkeyRegistering {
    /// Four-char signature 'LTxt' identifying our hotkeys.
    static let signature: OSType = 0x4C54_7874

    private var handlers: [UInt32: @MainActor (HotkeyEvent) -> Void] = [:]
    private var nextIdentifier: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    package init() {}

    package func register(
        _ combo: KeyCombo,
        handler: @escaping @MainActor (HotkeyEvent) -> Void
    ) throws(HotkeyError) -> any HotkeyRegistration {
        try installEventHandlerIfNeeded(for: combo)

        let identifier = makeIdentifier()
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            CarbonModifierFlags.flags(for: combo.modifiers),
            EventHotKeyID(signature: Self.signature, id: identifier),
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        // A non-noErr status (e.g. eventHotKeyExistsErr) is treated as "unavailable". Spike 0g decides
        // whether registration can also fail silently (status noErr, but the hotkey never fires).
        guard status == noErr, let hotKeyRef else {
            Logger.platform.error("RegisterEventHotKey failed (\(status)) for keyCode \(combo.keyCode)")
            removeEventHandlerIfIdle()
            throw .unavailable(combo)
        }
        handlers[identifier] = handler
        Logger.platform.info("Registered hotkey \(identifier) for keyCode \(combo.keyCode)")
        return CarbonHotkeyRegistration(identifier: identifier, hotKeyRef: hotKeyRef, registrar: self)
    }

    /// Called by `CarbonHotkeyRegistration.unregister()` after `UnregisterEventHotKey`.
    func removeHandler(identifier: UInt32) {
        handlers[identifier] = nil
        removeEventHandlerIfIdle()
    }

    /// Called from the Carbon callback (main thread). `kind` is `GetEventKind(event)`; `time` is
    /// `GetEventTime(event)`, read inside the callback.
    func handle(hotKeyID: EventHotKeyID, kind: UInt32, time: EventTime) -> OSStatus {
        let phase: HotkeyPhase
        switch kind {
        case UInt32(kEventHotKeyPressed): phase = .pressed
        case UInt32(kEventHotKeyReleased): phase = .released
        default: return OSStatus(eventNotHandledErr)
        }
        guard hotKeyID.signature == Self.signature, let handler = handlers[hotKeyID.id] else {
            return OSStatus(eventNotHandledErr)
        }
        handler(HotkeyEvent(phase: phase, at: time))
        return noErr
    }

    /// Test seam: adds a handler without `RegisterEventHotKey` or a Carbon event handler, and returns the
    /// identifier to pass to `handle(hotKeyID:kind:time:)`.
    func insertHandlerForTesting(_ handler: @escaping @MainActor (HotkeyEvent) -> Void) -> UInt32 {
        let identifier = makeIdentifier()
        handlers[identifier] = handler
        return identifier
    }

    private func makeIdentifier() -> UInt32 {
        let identifier = nextIdentifier
        nextIdentifier &+= 1
        return identifier
    }

    private func installEventHandlerIfNeeded(for combo: KeyCombo) throws(HotkeyError) {
        guard eventHandler == nil else { return }
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let retainedSelf = Unmanaged.passRetained(self)
        var handlerRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyEventCallback,
            eventTypes.count,
            &eventTypes,
            retainedSelf.toOpaque(),
            &handlerRef
        )
        guard status == noErr, let handlerRef else {
            retainedSelf.release()
            Logger.platform.error("InstallEventHandler failed (\(status))")
            throw .unavailable(combo)
        }
        eventHandler = handlerRef
    }

    private func removeEventHandlerIfIdle() {
        guard handlers.isEmpty, let eventHandler else { return }
        RemoveEventHandler(eventHandler)
        self.eventHandler = nil
        // Balances `passRetained` in `installEventHandlerIfNeeded`.
        Unmanaged.passUnretained(self).release()
    }
}

/// Carbon dispatches application-target events on the main thread. The time is read here, from the event
/// itself, so a busy main thread cannot skew tap-vs-hold timing (§3.1).
private func carbonHotKeyEventCallback(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    let kind = GetEventKind(event)
    let time = GetEventTime(event)
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let registrar = Unmanaged<CarbonHotkeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
    return MainActor.assumeIsolated {
        registrar.handle(hotKeyID: hotKeyID, kind: kind, time: time)
    }
}
