import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import LargeTextCore
import os

/// Live TCC checks (§2.6). Every read is fresh; nothing is cached.
@MainActor
package final class SystemPermissionsProvider: PermissionsProviding {
    static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    /// Value of `kAXTrustedCheckOptionPrompt` (spelled out to avoid touching the imported global `var`).
    static let trustedCheckOptionPrompt = "AXTrustedCheckOptionPrompt"

    package init() {}

    package var current: Permissions {
        Permissions(
            accessibility: AXIsProcessTrusted() ? .granted : .denied,
            eventPosting: CGPreflightPostEventAccess() ? .granted : .denied
        )
    }

    /// Shows the system Accessibility prompt. Must not be called while a session is active (§2.2).
    package func requestAccessibility() {
        logDiagnostics()
        let options = [Self.trustedCheckOptionPrompt: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        // Event posting is normally covered by the Accessibility grant. If AX is already trusted but
        // posting is not (unusual), ask for posting explicitly.
        if trusted, !CGPreflightPostEventAccess() {
            _ = CGRequestPostEventAccess()
        }
    }

    package func openSystemSettings() {
        NSWorkspace.shared.open(Self.accessibilitySettingsURL)
    }

    /// Diagnostics only — never a gate (stale Secure Input holders are common).
    package func logDiagnostics() {
        let permissions = current
        Logger.platform.info(
            """
            Permissions: accessibility=\(String(describing: permissions.accessibility), privacy: .public) \
            eventPosting=\(String(describing: permissions.eventPosting), privacy: .public) \
            secureEventInput=\(IsSecureEventInputEnabled(), privacy: .public)
            """
        )
    }
}
