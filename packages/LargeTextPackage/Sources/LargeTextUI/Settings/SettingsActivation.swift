import AppKit
import os

/// The activation-policy switch around the Settings window (Settings plan §3.3, D3).
@MainActor
package protocol SettingsActivation: AnyObject {
    /// Every time the window is shown, including when it is already open: makes LargeText a regular app
    /// (Dock icon, ⌘Tab entry, main menu) the first time, then unhides and activates it, so a repeated
    /// "Settings…" brings the window back from behind another app or after ⌘H.
    func activateForSettings()
    /// After the window closed: makes LargeText an accessory again and re-activates the app that was
    /// frontmost most recently before LargeText, so focus doesn't drop into an app with no window.
    func restoreAfterSettings()
}

/// The live switch, on `NSApp` and `NSWorkspace`.
@MainActor
package final class AppActivationSwitch: SettingsActivation {
    /// The last other app that was active while Settings is open; focus goes back there on close.
    private var previous: NSRunningApplication?
    private var activationObserver: (any NSObjectProtocol)?

    package init() {}

    package func activateForSettings() {
        if activationObserver == nil {
            remember(NSWorkspace.shared.frontmostApplication)
            NSApp.setActivationPolicy(.regular)
            // While Settings is open the user may switch to other apps; the latest one gets focus back.
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { self?.remember(app) }
            }
        }
        if NSApp.isHidden {
            NSApp.unhideWithoutActivation()
        }
        NSApp.activate()
        Logger.ui.debug("Settings: regular app (previous: \(self.previous?.bundleIdentifier ?? "none", privacy: .public))")
    }

    package func restoreAfterSettings() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        NSApp.setActivationPolicy(.accessory)
        // Not `NSApp.hide`: a hidden app may not show its non-activating panels afterwards.
        if let previous, !previous.isTerminated {
            NSApp.yieldActivation(to: previous)
            previous.activate()
        }
        previous = nil
        Logger.ui.debug("Settings: accessory app again")
    }

    private func remember(_ app: NSRunningApplication?) {
        guard let app, app != NSRunningApplication.current else { return }
        previous = app
    }
}
