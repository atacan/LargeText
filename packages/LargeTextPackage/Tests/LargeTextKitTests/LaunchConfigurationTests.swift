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
}
