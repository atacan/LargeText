import Foundation
import os

/// Logs instead of showing a card. Logs content kinds and lengths only, never the text (§4.10).
/// `dismiss()` returns at once; no intents are ever sent.
@MainActor
package final class LoggingReaderPresenter: ReaderPresenting {
    package init() {}

    package func present(
        sessionID: UUID,
        content: ReaderContent,
        chrome: ReaderChrome,
        intents: @escaping @MainActor (ReaderIntent) -> Void
    ) {
        Logger.core.info("LoggingReaderPresenter: present \(Self.summary(content), privacy: .public) (\(String(describing: chrome.mode), privacy: .public))")
    }

    package func update(content: ReaderContent, chrome: ReaderChrome) {
        Logger.core.debug("LoggingReaderPresenter: update \(Self.summary(content), privacy: .public)")
    }

    package func pointerMoved(_ sample: PointerSample) {}

    package func pin(content: ReaderContent, chrome: ReaderChrome) {
        Logger.core.info("LoggingReaderPresenter: pin \(Self.summary(content), privacy: .public)")
    }

    package func dismiss() async {
        Logger.core.info("LoggingReaderPresenter: dismiss")
    }

    private static func summary(_ content: ReaderContent) -> String {
        switch content {
        case .text(let text, _): "text(\(text.utf16.count) UTF-16 units)"
        case .hidden: "hidden"
        case .nothing: "nothing"
        }
    }
}
