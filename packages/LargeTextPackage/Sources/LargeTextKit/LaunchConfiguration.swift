import Foundation
import os

/// How the app was launched: an optional scenario and whether to open the editor right away.
public struct LaunchConfiguration: Equatable, Sendable {
    /// `--scenario <name>` or `--scenario=<name>`; unknown names are logged and ignored.
    package var scenario: Scenario?
    /// `--present-on-launch` → `coordinator.toggle()` after start.
    package var presentOnLaunch: Bool

    /// Parsed from the process arguments.
    public static var current: LaunchConfiguration {
        LaunchConfiguration(arguments: ProcessInfo.processInfo.arguments)
    }

    package init(scenario: Scenario? = nil, presentOnLaunch: Bool = false) {
        self.scenario = scenario
        self.presentOnLaunch = presentOnLaunch
    }

    /// Pure. Unknown arguments (e.g. Xcode's `-NSDocumentRevisionsDebugMode YES`) are ignored.
    package init(arguments: [String]) {
        var scenario: Scenario?
        var presentOnLaunch = false
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            var scenarioName: String?
            if argument == "--scenario" {
                let next = arguments.index(after: index)
                if next < arguments.endIndex {
                    scenarioName = arguments[next]
                    index = next
                } else {
                    Logger.kit.error("LaunchConfiguration: --scenario without a name")
                }
            } else if argument.hasPrefix("--scenario=") {
                scenarioName = String(argument.dropFirst("--scenario=".count))
            } else if argument == "--present-on-launch" {
                presentOnLaunch = true
            }
            if let scenarioName {
                if let parsed = Scenario(rawValue: scenarioName) {
                    scenario = parsed
                } else {
                    Logger.kit.error("LaunchConfiguration: unknown scenario '\(scenarioName, privacy: .public)' ignored")
                }
            }
            index = arguments.index(after: index)
        }
        self.init(scenario: scenario, presentOnLaunch: presentOnLaunch)
    }
}
