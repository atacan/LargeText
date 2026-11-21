import Foundation
import LargeTextCore

/// Records every state it is shown. `isVisible` follows `show` and `close()`, like a window.
@MainActor
package final class SpySettingsPresenter: SettingsPresenting {
    package private(set) var shown: [SettingsState] = []
    package private(set) var updates: [SettingsState] = []
    /// The most recent `show` or `update`.
    package private(set) var lastState: SettingsState?
    package var isVisible = false

    private var intents: (@MainActor (SettingsIntent) -> Void)?

    package init() {}

    package func show(_ state: SettingsState, intents: @escaping @MainActor (SettingsIntent) -> Void) {
        shown.append(state)
        lastState = state
        self.intents = intents
        isVisible = true
    }

    package func update(_ state: SettingsState) {
        updates.append(state)
        lastState = state
    }

    /// Sends `intent` through the closure from the last `show`, as the window would.
    package func send(_ intent: SettingsIntent) {
        intents?(intent)
    }

    /// The user closes the window: it is no longer visible, then `.closed` is sent.
    package func close() {
        isVisible = false
        send(.closed)
    }
}
