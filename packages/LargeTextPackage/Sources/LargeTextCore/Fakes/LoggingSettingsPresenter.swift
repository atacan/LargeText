import Foundation
import os

/// Logs instead of showing a window. Never visible, so the coordinator's permission refresh stops after its
/// first wait; no intents are ever sent.
@MainActor
package final class LoggingSettingsPresenter: SettingsPresenting {
    package init() {}

    package var isVisible: Bool { false }

    package func show(_ state: SettingsState, intents: @escaping @MainActor (SettingsIntent) -> Void) {
        Logger.core.info("LoggingSettingsPresenter: show (permission \(String(describing: state.permission), privacy: .public))")
    }

    package func update(_ state: SettingsState) {
        Logger.core.debug("LoggingSettingsPresenter: update")
    }
}
