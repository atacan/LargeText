import LargeTextCore
import SwiftUI

/// `ShortcutRecorderView` in `SettingsView`. The view's recording state follows `shortcut.isRecording`, and
/// each of its events becomes a `SettingsIntent` for `slot`.
struct ShortcutRecorderRepresentable: NSViewRepresentable {
    let slot: ShortcutSlot
    let shortcut: SettingsState.Shortcut
    let send: @MainActor (SettingsIntent) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView(frame: .zero)
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        let slot = slot
        let send = send
        view.title = SettingsStrings.shortcutTitle(slot)
        view.combo = shortcut.combo
        view.isRecording = shortcut.isRecording
        view.hasProblem = shortcut.problem != nil
        view.onBeginRecording = { send(.beginRecording(slot)) }
        view.onRecord = { send(.record(slot, $0)) }
        view.onCancel = { send(.cancelRecording) }
    }
}
