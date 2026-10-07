import CoreGraphics
import Foundation
import LargeTextCore
import LargeTextTestSupport

enum Fixtures {
    static let safari = TargetApplication(
        processIdentifier: 101, bundleIdentifier: "com.apple.Safari", localizedName: "Safari"
    )
    static let terminal = TargetApplication(
        processIdentifier: 202, bundleIdentifier: "com.apple.Terminal", localizedName: "Terminal"
    )
    static let frame = CGRect(x: 100, y: 200, width: 300, height: 40)

    static func target(
        _ application: TargetApplication? = safari,
        kind: ElementKind? = .singleLineText,
        selection: String? = nil
    ) -> FocusTarget {
        FocusTarget(application: application, elementKind: kind, selectedText: selection, frame: frame)
    }
}

/// A coordinator wired to TestSupport spies that all share one `EventLog`.
@MainActor
final class CoordinatorHarness {
    let log = EventLog()
    let focus: StubFocusCapturer
    let permissions: FixedPermissions
    let preferences = InMemoryPreferencesStore()
    let overlay: SpyOverlay
    let notices: SpyNotices
    let inserter: SpyInserter
    let coordinator: EditingSessionCoordinator

    init(target: FocusTarget = Fixtures.target(), permissions: Permissions = .allGranted, inserter: (any TextInserting)? = nil) {
        focus = StubFocusCapturer(target: target)
        self.permissions = FixedPermissions(permissions)
        overlay = SpyOverlay(log: log)
        notices = SpyNotices(log: log)
        self.inserter = SpyInserter(log: log)
        coordinator = EditingSessionCoordinator(dependencies: CoreDependencies(
            focus: focus,
            permissions: self.permissions,
            inserter: inserter ?? self.inserter,
            overlay: overlay,
            notices: notices,
            preferences: preferences
        ))
    }

    /// Toggles from idle and returns the presented session id (nil if nothing was presented).
    func open() async -> UUID? {
        let before = overlay.presentCount
        await coordinator.toggle()
        return overlay.presentCount > before ? overlay.lastSessionID : nil
    }

    func send(_ kind: OverlayIntent.Kind, to id: UUID) async {
        await coordinator.handle(OverlayIntent(sessionID: id, kind: kind))
    }
}
