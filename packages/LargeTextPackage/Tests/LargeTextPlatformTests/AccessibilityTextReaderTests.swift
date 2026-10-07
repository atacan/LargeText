import ApplicationServices
import LargeTextCore
import Testing
@testable import LargeTextPlatform

/// The reader's pure decisions. The AX calls themselves are exercised by hand (`--scenario reader-probe`).
@Suite struct AccessibilityTextReaderTests {
    /// A local element: creating it makes no cross-process call.
    static func target(bundleIdentifier: String?) -> AXHitTarget {
        AXHitTarget(
            element: AXUIElementCreateApplication(42),
            pid: 42,
            bundleIdentifier: bundleIdentifier,
            localizedName: "App",
            family: .native
        )
    }

    @Test(arguments: ["com.1password.1password", "com.apple.keychainaccess", "com.apple.Passwords"])
    func denylistedAppIsHiddenBeforeStageZero(bundleIdentifier: String) {
        #expect(AccessibilityTextReader.isDenylisted(Self.target(bundleIdentifier: bundleIdentifier), policy: .standard))
    }

    @Test(arguments: ["com.apple.Notes", nil] as [String?])
    func otherAppsAreRead(bundleIdentifier: String?) {
        #expect(!AccessibilityTextReader.isDenylisted(Self.target(bundleIdentifier: bundleIdentifier), policy: .standard))
    }

    @Test func denylistComesFromThePolicy() {
        let policy = ReadPolicy(denylist: ["com.apple.Notes"], elementTextLimit: 500, maxCharacters: 4_000)

        #expect(AccessibilityTextReader.isDenylisted(Self.target(bundleIdentifier: "com.apple.Notes"), policy: policy))
    }

    @Test func abortingErrorsMapToResults() {
        #expect(AccessibilityTextReader.result(for: .cannotComplete) == .nothing)
        #expect(AccessibilityTextReader.result(for: .apiDisabled) == .permissionMissing)
    }

    @Test func summaryNeverContainsTheText() {
        let text = ReadText(text: "Secret sentence.", granularity: .sentence, source: .unit)

        let summary = AccessibilityTextReader.summary(of: .text(text))

        #expect(!summary.contains("Secret"))
        #expect(summary.contains("length=16"))
    }
}
