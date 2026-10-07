import Carbon.HIToolbox
import LargeTextCore
import Testing
@testable import LargeTextPlatform

/// Routes events through the internal `handle(hotKeyID:kind:time:)` seam; never calls `RegisterEventHotKey`.
@Suite @MainActor struct CarbonHotkeyRegistrarTests {
    let registrar = CarbonHotkeyRegistrar()

    func hotKeyID(_ identifier: UInt32, signature: OSType = CarbonHotkeyRegistrar.signature) -> EventHotKeyID {
        EventHotKeyID(signature: signature, id: identifier)
    }

    @Test func routesPressedAndReleasedWithEventTime() {
        var received: [HotkeyEvent] = []
        let identifier = registrar.insertHandlerForTesting { received.append($0) }

        let pressed = registrar.handle(hotKeyID: hotKeyID(identifier), kind: UInt32(kEventHotKeyPressed), time: 10.25)
        let released = registrar.handle(hotKeyID: hotKeyID(identifier), kind: UInt32(kEventHotKeyReleased), time: 10.5)

        #expect(pressed == noErr)
        #expect(released == noErr)
        #expect(received == [
            HotkeyEvent(phase: .pressed, at: 10.25),
            HotkeyEvent(phase: .released, at: 10.5),
        ])
    }

    @Test func routesToTheMatchingHandlerOnly() {
        var first: [HotkeyPhase] = []
        var second: [HotkeyPhase] = []
        let firstID = registrar.insertHandlerForTesting { first.append($0.phase) }
        let secondID = registrar.insertHandlerForTesting { second.append($0.phase) }
        #expect(firstID != secondID)

        _ = registrar.handle(hotKeyID: hotKeyID(secondID), kind: UInt32(kEventHotKeyReleased), time: 1)

        #expect(first.isEmpty)
        #expect(second == [.released])
    }

    @Test func ignoresForeignSignatureUnknownIdentifierAndOtherKinds() {
        var received: [HotkeyEvent] = []
        let identifier = registrar.insertHandlerForTesting { received.append($0) }
        let notHandled = OSStatus(eventNotHandledErr)

        #expect(registrar.handle(hotKeyID: hotKeyID(identifier, signature: 0x4142_4344), kind: UInt32(kEventHotKeyPressed), time: 1) == notHandled)
        #expect(registrar.handle(hotKeyID: hotKeyID(identifier + 1), kind: UInt32(kEventHotKeyPressed), time: 1) == notHandled)
        #expect(registrar.handle(hotKeyID: hotKeyID(identifier), kind: UInt32(kEventRawKeyDown), time: 1) == notHandled)
        #expect(received.isEmpty)
    }

    @Test func registerPressOnlyDropsReleases() throws {
        var presses = 0
        let spy = PressOnlyProbe()
        _ = try spy.registerPressOnly(.default) { presses += 1 }

        spy.handler?(HotkeyEvent(phase: .pressed, at: 1))
        spy.handler?(HotkeyEvent(phase: .released, at: 2))

        #expect(presses == 1)
    }
}

/// Captures the handler that `registerPressOnly` wraps (TestSupport isn't a Platform test dependency).
@MainActor
private final class PressOnlyProbe: HotkeyRegistering {
    private final class Registration: HotkeyRegistration {
        func unregister() {}
    }

    private(set) var handler: (@MainActor (HotkeyEvent) -> Void)?

    func register(
        _ combo: KeyCombo,
        handler: @escaping @MainActor (HotkeyEvent) -> Void
    ) throws(HotkeyError) -> any HotkeyRegistration {
        self.handler = handler
        return Registration()
    }
}
