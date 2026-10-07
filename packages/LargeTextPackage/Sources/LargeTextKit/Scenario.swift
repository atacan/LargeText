import Foundation
import LargeTextCore

/// Launch-time states for hands-on testing (`--scenario <rawValue>`), compiled unconditionally (§3.2).
///
/// A scenario only mutates the `AppEnvironment` before assembly. Every scenario swaps in an
/// `InMemoryPreferencesStore`, so zooming or other preference writes never touch the real defaults.
/// Kit-owned responsibilities (activation policy, status item, hotkey, permission request) stay live.
///
/// Note: with `inserterOverride` set, the overlay's header hints still reflect the real `InsertionRoute`.
package enum Scenario: String, CaseIterable, Sendable {
    /// Focus: stub Safari URL bar with the selection "https://www.apple.com". Inserter: `LoggingTextInserter`.
    /// Live: hotkey, permissions, overlay, HUD. Nothing is pasted. Use with `--present-on-launch`.
    case overlayPrefilled = "overlay-prefilled"
    /// Focus: stub Safari target whose element is `.notEditable`. Live: permissions, real pasteboard,
    /// real `PasteboardTextInserter`, overlay, HUD → commit copies to the clipboard and shows the HUD.
    case noEditableTarget = "no-editable-target"
    /// Permissions: `FixedPermissions(.allDenied)` (and no system prompt). Live: focus capture, real pasteboard,
    /// real `PasteboardTextInserter`, overlay, HUD → commit is copy-only with the "permission missing" HUD.
    case permissionMissing = "permission-missing"
    /// Inserter: `LoggingTextInserter`. Everything else is live, including focus capture and permissions.
    case loggingInsertion = "logging-insertion"

    @MainActor
    package func apply(to environment: inout AppEnvironment) {
        environment.preferences = InMemoryPreferencesStore()
        switch self {
        case .overlayPrefilled:
            environment.focus = StubFocusCapturer(target: Self.safariTarget(kind: .singleLineText, selection: "https://www.apple.com"))
            environment.inserterOverride = LoggingTextInserter()
        case .noEditableTarget:
            environment.focus = StubFocusCapturer(target: Self.safariTarget(kind: .notEditable, selection: nil))
        case .permissionMissing:
            environment.permissions = FixedPermissions(.allDenied)
        case .loggingInsertion:
            environment.inserterOverride = LoggingTextInserter()
        }
    }

    @MainActor
    private static func safariTarget(kind: ElementKind, selection: String?) -> FocusTarget {
        FocusTarget(
            application: TargetApplication(
                processIdentifier: 0,
                bundleIdentifier: "com.apple.Safari",
                localizedName: "Safari"
            ),
            elementKind: kind,
            selectedText: selection
        )
    }
}
