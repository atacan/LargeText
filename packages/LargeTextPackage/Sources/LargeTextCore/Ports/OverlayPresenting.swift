import Foundation

@MainActor
package protocol OverlayPresenting: AnyObject {
    /// Resets undo; `initialText` is applied once and fully selected if non-empty.
    /// Afterwards the view owns the text.
    func present(
        sessionID: UUID,
        initialText: String,
        chrome: OverlayChrome,
        intents: @escaping @MainActor (OverlayIntent) -> Void
    )
    /// Never touches the text.
    func update(_ chrome: OverlayChrome)
    /// Stops emitting intents immediately, discards marked text, orders out (fade),
    /// and returns the text. This is the ONLY way the coordinator obtains the text.
    func dismiss() async -> String
}
