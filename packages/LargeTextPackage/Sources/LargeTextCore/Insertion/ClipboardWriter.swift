import Foundation
import os

/// The shared copy-only exit. Writes non-transient text: the user pastes it by hand,
/// so clipboard-manager history is fine here.
@MainActor
package struct ClipboardWriter {
    package let pasteboard: any PasteboardClient

    package init(pasteboard: any PasteboardClient) {
        self.pasteboard = pasteboard
    }

    package func copy(_ text: String, reason: InsertionFallbackReason) -> InsertionOutcome {
        pasteboard.write(text, transient: false)
        Logger.core.info("Insertion: copied to clipboard (\(String(describing: reason)))")
        return .copiedToClipboard(reason)
    }
}
