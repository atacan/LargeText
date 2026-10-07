import LargeTextCore
import LargeTextTestSupport
import Testing
@testable import LargeTextKit

@Suite struct LaunchConfigurationTests {
    private let executable = "/Applications/LargeText.app/Contents/MacOS/LargeText"

    @Test func noArgumentsMeansLiveWithoutPresenting() {
        let configuration = LaunchConfiguration(arguments: [executable])
        #expect(configuration.scenario == nil)
        #expect(configuration.presentOnLaunch == false)
        #expect(configuration == LaunchConfiguration())
    }

    @Test func emptyArgumentList() {
        #expect(LaunchConfiguration(arguments: []) == LaunchConfiguration())
    }

    @Test(arguments: Scenario.allCases)
    func scenarioAsSeparateArgument(_ scenario: Scenario) {
        let configuration = LaunchConfiguration(arguments: [executable, "--scenario", scenario.rawValue])
        #expect(configuration.scenario == scenario)
        #expect(configuration.presentOnLaunch == false)
    }

    @Test func scenarioWithEqualsSign() {
        let configuration = LaunchConfiguration(arguments: [executable, "--scenario=permission-missing"])
        #expect(configuration.scenario == .permissionMissing)
    }

    @Test func unknownScenarioIsIgnored() {
        let configuration = LaunchConfiguration(arguments: [executable, "--scenario", "does-not-exist", "--present-on-launch"])
        #expect(configuration.scenario == nil)
        #expect(configuration.presentOnLaunch)
    }

    @Test func scenarioWithoutNameIsIgnored() {
        #expect(LaunchConfiguration(arguments: [executable, "--scenario"]) == LaunchConfiguration())
    }

    @Test func presentOnLaunch() {
        let configuration = LaunchConfiguration(arguments: [executable, "--scenario", "overlay-prefilled", "--present-on-launch"])
        #expect(configuration == LaunchConfiguration(scenario: .overlayPrefilled, presentOnLaunch: true))
    }

    @Test func xcodeNoiseArgumentsAreIgnored() {
        let configuration = LaunchConfiguration(arguments: [
            executable,
            "-NSDocumentRevisionsDebugMode", "YES",
            "-ApplePersistenceIgnoreState", "YES",
            "--present-on-launch",
            "--scenario", "logging-insertion",
            "-AppleLanguages", "(en)",
        ])
        #expect(configuration == LaunchConfiguration(scenario: .loggingInsertion, presentOnLaunch: true))
    }

    @Test func scenarioNameIsNotReadAsAFlag() {
        // "--present-on-launch" right after "--scenario" is consumed as the (unknown) scenario name.
        let configuration = LaunchConfiguration(arguments: [executable, "--scenario", "--present-on-launch"])
        #expect(configuration == LaunchConfiguration())
    }

    // MARK: - Reader

    @Test(arguments: ReaderLaunchState.allCases)
    func presentReaderOnLaunchImpliesTheReaderStub(_ state: ReaderLaunchState) {
        let configuration = LaunchConfiguration(arguments: [executable, "--present-reader-on-launch=\(state.rawValue)"])
        #expect(configuration.presentReaderOnLaunch == state)
        #expect(configuration.scenario == .readerStub)
        #expect(configuration.presentOnLaunch == false)
    }

    @Test func presentReaderOnLaunchAsSeparateArgumentReplacesAnotherScenario() {
        let configuration = LaunchConfiguration(arguments: [
            executable, "--scenario", "logging-insertion", "--present-reader-on-launch", "long",
        ])
        #expect(configuration == LaunchConfiguration(scenario: .readerStub, presentReaderOnLaunch: .long))
    }

    @Test func unknownReaderStateIsIgnored() {
        let configuration = LaunchConfiguration(arguments: [executable, "--present-reader-on-launch=sideways"])
        #expect(configuration == LaunchConfiguration())
    }

    @Test func readerTunables() {
        let configuration = LaunchConfiguration(arguments: [
            executable, "--reader-hold-threshold", "450", "--following-unit=paragraph", "--reader-stub-delay=250",
        ])
        #expect(configuration.readerHoldThreshold == .milliseconds(450))
        #expect(configuration.followingUnit == .paragraph)
        #expect(configuration.readerStubDelay == .milliseconds(250))
        #expect(configuration.scenario == nil)
    }

    @Test(arguments: ["-5", "fast", "1.5"])
    func malformedHoldThresholdIsIgnored(_ value: String) {
        let configuration = LaunchConfiguration(arguments: [executable, "--reader-hold-threshold", value])
        #expect(configuration.readerHoldThreshold == nil)
    }

    @Test func unknownFollowingUnitIsIgnored() {
        #expect(LaunchConfiguration(arguments: [executable, "--following-unit", "word"]).followingUnit == nil)
    }

    @Test func onlyTheFollowingStateDisablesTheCap() {
        #expect(LaunchConfiguration(presentReaderOnLaunch: .following).readerTiming == ReaderTiming(maxFollowDuration: nil))
        #expect(LaunchConfiguration(presentReaderOnLaunch: .pinned).readerTiming == .standard)
        #expect(LaunchConfiguration().readerTiming == .standard)
    }

    // MARK: - Applying to the environment

    @MainActor
    func environment(preferences: any PreferencesStore = InMemoryPreferencesStore()) -> AppEnvironment {
        AppEnvironment(
            hotkeys: SpyHotkeys(),
            focus: StubFocusCapturer(target: FocusTarget(application: nil)),
            permissions: FixedPermissions(.allDenied),
            pasteboard: FakePasteboard(),
            keystrokes: RecordingKeystrokes(),
            preferences: preferences,
            sleeper: InstantSleeper(),
            overlay: SpyOverlay(),
            notices: SpyNotices()
        )
    }

    @MainActor
    @Test func followingStateHoldsTheKeyDownAndKeepsTheXBandStub() throws {
        var environment = environment()

        LaunchConfiguration(presentReaderOnLaunch: .following).apply(to: &environment)

        let keyState = try #require(environment.keyState as? FixedKeyState)
        #expect(keyState.isDown == true)
        let stub = try #require(environment.textReader as? StubTextReader)
        #expect(stub.answers.count == 3)
    }

    @MainActor
    @Test(arguments: [
        (ReaderLaunchState.pinned, Scenario.stubLabel),
        (.nothing, .nothing),
        (.hidden, .hidden),
        (.long, Scenario.stubParagraph),
    ])
    func tapStatesAnswerTheSameEverywhere(_ state: ReaderLaunchState, result: ReadResult) throws {
        var environment = environment()

        LaunchConfiguration(presentReaderOnLaunch: state, readerStubDelay: .milliseconds(300)).apply(to: &environment)

        let stub = try #require(environment.textReader as? StubTextReader)
        #expect(stub.answers.isEmpty)
        #expect(stub.fallback == result)
        #expect(stub.delay == .milliseconds(300))
        #expect(environment.permissions.current == .allGranted)
        #expect(environment.keyState is FixedKeyState)
    }

    @MainActor
    @Test func tunablesAreAnInMemoryOverlay() {
        let base = InMemoryPreferencesStore(readerHoldThreshold: .milliseconds(300), followingUnit: .sentence)
        var environment = environment(preferences: base)

        LaunchConfiguration(readerHoldThreshold: .milliseconds(600), followingUnit: .line).apply(to: &environment)
        let preferences = environment.preferences
        preferences.readerHoldThreshold = .milliseconds(700)
        preferences.fontSize = FontSize(points: 90)

        #expect(preferences.readerHoldThreshold == .milliseconds(700))
        #expect(preferences.followingUnit == .line)
        // Overridden keys never reach the store underneath; the others still do.
        #expect(base.readerHoldThreshold == .milliseconds(300))
        #expect(base.followingUnit == .sentence)
        #expect(base.fontSize == FontSize(points: 90))
    }

    @MainActor
    @Test func withoutTunablesThePreferencesAreUntouched() {
        let base = InMemoryPreferencesStore()
        var environment = environment(preferences: base)

        LaunchConfiguration().apply(to: &environment)

        #expect(environment.preferences === base)
    }
}
