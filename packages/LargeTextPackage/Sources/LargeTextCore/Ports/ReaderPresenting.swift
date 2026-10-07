import Foundation

@MainActor
package protocol ReaderPresenting: AnyObject {
    /// Shows the card in `chrome.mode`. Intents carry `sessionID`; stale ones are ignored by the coordinator.
    func present(
        sessionID: UUID,
        content: ReaderContent,
        chrome: ReaderChrome,
        intents: @escaping @MainActor (ReaderIntent) -> Void
    )
    /// New content or chrome for the current session, without animation while following.
    func update(content: ReaderContent, chrome: ReaderChrome)
    /// Every tick while following; drives placement hysteresis (§4.6).
    func pointerMoved(_ sample: PointerSample)
    /// Following → pinned without moving the card. The pinned unit and source frame change at pin.
    func pin(content: ReaderContent, chrome: ReaderChrome)
    /// Stops emitting intents immediately, then fades out. Returns once the panel is gone.
    func dismiss() async
}
