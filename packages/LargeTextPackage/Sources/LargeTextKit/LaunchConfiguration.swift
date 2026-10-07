import Foundation
import LargeTextCore
import os

/// How the app was launched: an optional scenario, whether to open the editor or the reader right away, and
/// the reader tunables to try without a settings UI.
public struct LaunchConfiguration: Equatable, Sendable {
    /// `--scenario <name>` or `--scenario=<name>`; unknown names are logged and ignored.
    package var scenario: Scenario?
    /// `--present-on-launch` → the editor opens after start.
    package var presentOnLaunch: Bool
    /// `--present-reader-on-launch=<state>` → a scripted reader gesture after start. Implies `reader-stub`.
    package var presentReaderOnLaunch: ReaderLaunchState?
    /// `--reader-hold-threshold <ms>`: overrides the preference in memory only.
    package var readerHoldThreshold: Duration?
    /// `--following-unit <sentence|line|paragraph>`: overrides the preference in memory only.
    package var followingUnit: ReadGranularity?
    /// `--reader-stub-delay <ms>`: how long the stub reader waits before answering, to try races by hand.
    package var readerStubDelay: Duration?

    /// Parsed from the process arguments.
    public static var current: LaunchConfiguration {
        LaunchConfiguration(arguments: ProcessInfo.processInfo.arguments)
    }

    /// A reader launch state needs the stub reader's text, so it replaces any other scenario with `reader-stub`.
    package init(
        scenario: Scenario? = nil,
        presentOnLaunch: Bool = false,
        presentReaderOnLaunch: ReaderLaunchState? = nil,
        readerHoldThreshold: Duration? = nil,
        followingUnit: ReadGranularity? = nil,
        readerStubDelay: Duration? = nil
    ) {
        if presentReaderOnLaunch != nil, let scenario, scenario != .readerStub {
            Logger.kit.error("LaunchConfiguration: --present-reader-on-launch replaces scenario '\(scenario.rawValue, privacy: .public)' with reader-stub")
        }
        self.scenario = presentReaderOnLaunch == nil ? scenario : .readerStub
        self.presentOnLaunch = presentOnLaunch
        self.presentReaderOnLaunch = presentReaderOnLaunch
        self.readerHoldThreshold = readerHoldThreshold
        self.followingUnit = followingUnit
        self.readerStubDelay = readerStubDelay
    }

    /// Pure. Options with a value take it as the next argument or after `=`. Unknown arguments (e.g. Xcode's
    /// `-NSDocumentRevisionsDebugMode YES`) are ignored; unknown or malformed values are logged and leave the
    /// option as it was.
    package init(arguments: [String]) {
        var parsed = LaunchConfiguration()
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            if argument == "--present-on-launch" {
                parsed.presentOnLaunch = true
            } else if let (option, inlineValue) = ValueOption.match(argument) {
                var value = inlineValue
                if value == nil {
                    let next = arguments.index(after: index)
                    if next < arguments.endIndex {
                        value = arguments[next]
                        index = next
                    }
                }
                if let value {
                    parsed.set(option, to: value)
                } else {
                    Logger.kit.error("LaunchConfiguration: \(option.rawValue, privacy: .public) without a value")
                }
            }
            index = arguments.index(after: index)
        }
        self.init(
            scenario: parsed.scenario,
            presentOnLaunch: parsed.presentOnLaunch,
            presentReaderOnLaunch: parsed.presentReaderOnLaunch,
            readerHoldThreshold: parsed.readerHoldThreshold,
            followingUnit: parsed.followingUnit,
            readerStubDelay: parsed.readerStubDelay
        )
    }

    /// The reader timers: the `following` launch state holds its session open on purpose, so it has no cap.
    package var readerTiming: ReaderTiming {
        presentReaderOnLaunch == .following ? ReaderTiming(maxFollowDuration: nil) : .standard
    }

    /// Mutates the environment before assembly: the scenario, then the reader launch state, the stub delay
    /// and the preference overlay.
    @MainActor
    package func apply(to environment: inout AppEnvironment) {
        if let scenario {
            Logger.kit.info("Applying scenario \(scenario.rawValue, privacy: .public)")
            scenario.apply(to: &environment)
        }
        if let presentReaderOnLaunch {
            presentReaderOnLaunch.apply(to: &environment)
        }
        if let readerStubDelay, var stub = environment.textReader as? StubTextReader {
            stub.delay = readerStubDelay
            environment.textReader = stub
        }
        if readerHoldThreshold != nil || followingUnit != nil {
            environment.preferences = PreferencesOverlay(
                base: environment.preferences,
                readerHoldThreshold: readerHoldThreshold,
                followingUnit: followingUnit
            )
        }
    }

    // MARK: - Parsing

    private enum ValueOption: String, CaseIterable {
        case scenario = "--scenario"
        case presentReaderOnLaunch = "--present-reader-on-launch"
        case readerHoldThreshold = "--reader-hold-threshold"
        case followingUnit = "--following-unit"
        case readerStubDelay = "--reader-stub-delay"

        /// The option and its `=` value, if any.
        static func match(_ argument: String) -> (ValueOption, String?)? {
            for option in allCases {
                if argument == option.rawValue { return (option, nil) }
                if argument.hasPrefix(option.rawValue + "=") {
                    return (option, String(argument.dropFirst(option.rawValue.count + 1)))
                }
            }
            return nil
        }
    }

    private mutating func set(_ option: ValueOption, to value: String) {
        switch option {
        case .scenario:
            scenario = Self.parse(value, for: option, as: Scenario.init(rawValue:)) ?? scenario
        case .presentReaderOnLaunch:
            presentReaderOnLaunch = Self.parse(value, for: option, as: ReaderLaunchState.init(rawValue:)) ?? presentReaderOnLaunch
        case .readerHoldThreshold:
            readerHoldThreshold = Self.parse(value, for: option, as: Self.milliseconds) ?? readerHoldThreshold
        case .followingUnit:
            followingUnit = Self.parse(value, for: option, as: ReadGranularity.init(rawValue:)) ?? followingUnit
        case .readerStubDelay:
            readerStubDelay = Self.parse(value, for: option, as: Self.milliseconds) ?? readerStubDelay
        }
    }

    private static func parse<Value>(_ value: String, for option: ValueOption, as parse: (String) -> Value?) -> Value? {
        guard let parsed = parse(value) else {
            Logger.kit.error("LaunchConfiguration: unknown \(option.rawValue, privacy: .public) value '\(value, privacy: .public)' ignored")
            return nil
        }
        return parsed
    }

    /// A non-negative whole number of milliseconds.
    private static func milliseconds(_ value: String) -> Duration? {
        guard let milliseconds = Int(value), milliseconds >= 0 else { return nil }
        return .milliseconds(milliseconds)
    }
}

/// `--present-reader-on-launch=<state>`: a reader card in a known state without holding four keys (§5.4).
package enum ReaderLaunchState: String, CaseIterable, Sendable {
    /// A tap on a short label: the pinned card.
    case pinned
    /// A press with no release over the live pointer, to watch placement and hysteresis. The stub answers by
    /// pointer x; the key reads as held and there is no 30 s cap.
    case following
    /// A tap on nothing: the "No readable text" HUD.
    case nothing
    /// A tap on hidden text: the pinned "Hidden text" card.
    case hidden
    /// A tap on a long paragraph: the pinned card scrolls.
    case long

    /// A tap releases at once; `following` never releases.
    package var releasesAtOnce: Bool {
        self != .following
    }

    /// After `reader-stub`: a tap state answers the same wherever the pointer is.
    @MainActor
    func apply(to environment: inout AppEnvironment) {
        switch self {
        case .following:
            environment.keyState = FixedKeyState(isDown: true)
        case .pinned:
            environment.textReader = StubTextReader(fallback: Scenario.stubLabel)
        case .nothing:
            environment.textReader = StubTextReader(fallback: .nothing)
        case .hidden:
            environment.textReader = StubTextReader(fallback: .hidden)
        case .long:
            environment.textReader = StubTextReader(fallback: Scenario.stubParagraph)
        }
    }
}
