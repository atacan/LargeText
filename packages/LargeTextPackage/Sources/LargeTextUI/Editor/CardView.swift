import AppKit

/// The rounded HUD-material card. Swallows clicks so they never reach the backdrop (which would cancel).
@MainActor
final class CardView: NSVisualEffectView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        // Intentionally empty: a click on the card's chrome is not a backdrop click.
    }
}
