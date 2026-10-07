import AppKit

extension NSScreen {
    /// `CGDirectDisplayID`, or 0 if AppKit doesn't report one.
    var displayID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    var descriptor: ScreenDescriptor {
        ScreenDescriptor(id: displayID, frame: frame, visibleFrame: visibleFrame)
    }

    /// Resolves the live screen for the target frame / mouse via `ScreenResolver`.
    @MainActor
    static func resolve(targetFrame: CGRect?) -> NSScreen? {
        let screens = NSScreen.screens
        guard let chosen = ScreenResolver.resolve(
            targetFrame: targetFrame,
            mouseLocation: NSEvent.mouseLocation,
            screens: screens.map(\.descriptor)
        ) else { return nil }
        return screens.first { $0.displayID == chosen.id && $0.frame == chosen.frame } ?? screens.first
    }
}
