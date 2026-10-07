import AppKit
import LargeTextCore
import LargeTextPlatform
import LargeTextUI
import os

/// Owns the app lifecycle and the Kit-owned responsibilities (§3.9): activation policy, status item,
/// global hotkey and the one-time accessibility request. Never touches `NSApp.mainMenu`.
@MainActor
package final class AppController: NSObject, NSApplicationDelegate {
    private let environment: AppEnvironment
    private let launch: LaunchConfiguration

    package private(set) var coordinator: EditingSessionCoordinator?
    private var statusItem: StatusItemController?
    private var hotkeyRegistration: (any HotkeyRegistration)?

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
            presentOnLaunch: \(self.launch.presentOnLaunch, privacy: .public))
            """
        )

        // 1. Activation policy (LSUIElement already makes us an accessory app; this is defensive).
        NSApplication.shared.setActivationPolicy(.accessory)

        // 2. Coordinator. Assembly runs after any scenario mutation.
        let coordinator = EditingSessionCoordinator(dependencies: environment.coreDependencies())
        self.coordinator = coordinator

        // 3. Status item.
        let hotkey = environment.preferences.hotkey
        let statusItem = StatusItemController(hotkey: hotkey, permissions: environment.permissions) {
            Task { await coordinator.toggle() }
        }
        statusItem.install()
        self.statusItem = statusItem

        // 4. Global hotkey.
        do {
            hotkeyRegistration = try environment.hotkeys.register(hotkey) {
                Task { await coordinator.toggle() }
            }
        } catch {
            Logger.kit.error("Hotkey unavailable: \(String(describing: error), privacy: .public)")
            if case .unavailable(let combo) = error {
                statusItem.hotkeyUnavailable = combo
                environment.notices.show(.hotkeyUnavailable(combo))
            }
        }

        // 5. Ask for Accessibility once, outside any session. (The AX messaging timeout is configured
        //    lazily by AccessibilityFocusCapturer on first use.)
        let permissions = environment.permissions.current
        if permissions.accessibility == .denied || permissions.eventPosting == .denied {
            Logger.kit.info("Accessibility or event posting missing; requesting access")
            environment.permissions.requestAccessibility()
        } else if let system = environment.permissions as? SystemPermissionsProvider {
            system.logDiagnostics()
        }

        // 6. Present on launch.
        if launch.presentOnLaunch {
            Task { await coordinator.toggle() }
        }
    }

    package func stop() {
        hotkeyRegistration?.unregister()
        hotkeyRegistration = nil
        statusItem?.remove()
        statusItem = nil
        Logger.kit.info("Stopped")
    }
}
