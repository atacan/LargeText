import Testing
import LargeTextCore
import LargeTextTestSupport

/// One row of the §2.5 route table, plus what the overlay should show and what ends up on the pasteboard.
struct RouteRow: Sendable, CustomTestStringConvertible {
    let name: String
    let application: TargetApplication?
    let kind: ElementKind?
    let permissions: Permissions
    let route: InsertionRoute
    let flattens: Bool

    var testDescription: String { name }

    static let denied = Permissions(accessibility: .granted, eventPosting: .denied)

    static let all: [RouteRow] = [
        RouteRow(name: "event posting denied", application: Fixtures.safari, kind: .singleLineText,
                 permissions: denied, route: .copyOnly(.permissionMissing), flattens: false),
        RouteRow(name: "LargeText was frontmost", application: nil, kind: nil,
                 permissions: .allGranted, route: .copyOnly(.noEditableTarget), flattens: false),
        RouteRow(name: "not editable", application: Fixtures.safari, kind: .notEditable,
                 permissions: .allGranted, route: .copyOnly(.noEditableTarget), flattens: false),
        RouteRow(name: "unknown element", application: Fixtures.safari, kind: nil,
                 permissions: .allGranted, route: .paste, flattens: false),
        RouteRow(name: "single-line field", application: Fixtures.safari, kind: .singleLineText,
                 permissions: .allGranted, route: .paste, flattens: true),
        RouteRow(name: "multi-line field", application: Fixtures.safari, kind: .multiLineText,
                 permissions: .allGranted, route: .paste, flattens: false),
        RouteRow(name: "terminal, unknown element", application: Fixtures.terminal, kind: nil,
                 permissions: .allGranted, route: .paste, flattens: true),
        RouteRow(name: "accessibility denied only", application: Fixtures.safari, kind: nil,
                 permissions: Permissions(accessibility: .denied, eventPosting: .granted), route: .paste, flattens: false),
    ]

    var target: FocusTarget { Fixtures.target(application, kind: kind) }
}

@MainActor
struct InsertionRouteTests {
    @Test(arguments: RouteRow.all)
    func decideMatchesTable(row: RouteRow) {
        #expect(InsertionRoute.decide(target: row.target, permissions: row.permissions) == row.route)
    }

    @Test func secureTextDefensivelyRoutesToPaste() {
        #expect(InsertionRoute.decide(target: Fixtures.target(kind: .secureText), permissions: .allGranted) == .paste)
    }

    @Test func eventPostingIsCheckedBeforeTheTarget() {
        let route = InsertionRoute.decide(target: Fixtures.target(nil, kind: .notEditable), permissions: RouteRow.denied)
        #expect(route == .copyOnly(.permissionMissing))
    }

    /// The hints shown at open and the real inserter's outcome at commit agree with `InsertionRoute.decide`.
    @Test(arguments: RouteRow.all)
    func hintsAndInserterAgreeWithRoute(row: RouteRow) async throws {
        let pasteboard = FakePasteboard(items: [.text("original")])
        let preferences = InMemoryPreferencesStore()
        let permissions = FixedPermissions(row.permissions)
        let focus = StubFocusCapturer(target: row.target)
        let inserter = PasteboardTextInserter(
            permissions: permissions, pasteboard: pasteboard, keystrokes: RecordingKeystrokes(), focus: focus,
            preferences: preferences, sleeper: RecordingSleeper()
        )
        let harness = CoordinatorHarness(target: row.target, permissions: row.permissions, inserter: inserter)

        let id = try #require(await harness.open())
        let hints = try #require(harness.overlay.lastChrome?.hints)
        #expect(hints == TargetHints(willCopyToClipboard: row.route != .paste, flattensNewlines: row.flattens))

        harness.overlay.textToReturn = "a\nb"
        await harness.send(.commit(.insert), to: id)
        await inserter.pendingRestore?.value

        switch row.route {
        case .paste:
            #expect(harness.notices.shown.isEmpty)
            #expect(pasteboard.writes.map(\.string) == [row.flattens ? "a b" : "a\nb"])
            #expect(pasteboard.writes.map(\.transient) == [true])
        case .copyOnly(let reason):
            #expect(harness.notices.shown == [.copiedToClipboard(reason)])
            #expect(pasteboard.writes.map(\.string) == ["a\nb"])
            #expect(pasteboard.writes.map(\.transient) == [false])
        }
    }
}
