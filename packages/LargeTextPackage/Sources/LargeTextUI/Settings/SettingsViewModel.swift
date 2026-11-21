import LargeTextCore
import Observation

/// What `SettingsView` observes. It holds the last `SettingsState` from `SettingsCoordinator` and sends
/// every change back as a `SettingsIntent`; it never changes `state` itself, so the window always shows what
/// the coordinator saved (a clamped size, a refused shortcut).
@MainActor
@Observable
package final class SettingsViewModel {
    package var state: SettingsState
    /// Replaced by each `SettingsWindowController.show`.
    @ObservationIgnored package var intents: @MainActor (SettingsIntent) -> Void

    package init(state: SettingsState, intents: @escaping @MainActor (SettingsIntent) -> Void = { _ in }) {
        self.state = state
        self.intents = intents
    }

    package func send(_ intent: SettingsIntent) {
        intents(intent)
    }

    // MARK: - Slider values

    /// The stored threshold in whole milliseconds, clamped to what the slider offers (a `defaults write`
    /// value may lie outside it).
    package var holdThresholdMilliseconds: Double {
        Self.milliseconds(ReaderDefaults.clampHoldThreshold(state.holdThreshold))
    }

    package func setHoldThreshold(milliseconds: Double) {
        send(.setHoldThreshold(.milliseconds(Int(milliseconds.rounded()))))
    }

    package static var holdThresholdRange: ClosedRange<Double> {
        milliseconds(ReaderDefaults.holdThresholdRange.lowerBound)...milliseconds(ReaderDefaults.holdThresholdRange.upperBound)
    }

    package static var holdThresholdStep: Double {
        milliseconds(ReaderDefaults.holdThresholdStep)
    }

    package static func milliseconds(_ duration: Duration) -> Double {
        let (seconds, attoseconds) = duration.components
        return (Double(seconds) * 1_000 + Double(attoseconds) / 1e15).rounded()
    }
}
