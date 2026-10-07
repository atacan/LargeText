import AppKit
import LargeTextCore

// Fast visual loop for the reader card (select the package scheme in Xcode). The card is placed in the
// preview's 1440×900 root view with `ReaderPlacement`; ⌘C / ⌘A work, close and zoom are no-ops because
// no window controller is attached.

@MainActor
private func readerPreview(_ content: ReaderContent, chrome: ReaderChrome) -> ReaderViewController {
    let controller = ReaderViewController()
    controller.render(content: content, chrome: chrome)
    let bounds = controller.view.bounds
    let pinned = chrome.mode == .pinned
    let heightFraction = pinned ? Theme.editorMaxHeightFraction : Theme.followingMaxHeightFraction
    let size = controller.preferredCardSize(
        width: (bounds.width * Theme.cardWidthFraction).rounded(),
        maxHeight: (bounds.height * heightFraction).rounded(.down)
    )
    let frame = if pinned {
        ReaderPlacement.pinned(in: bounds, preferredSize: size, previous: nil)
    } else {
        // Pointer near the bottom, so the following card sits at the top.
        ReaderPlacement.following(
            in: bounds,
            pointer: CGPoint(x: bounds.midX, y: bounds.height * 0.2),
            sourceFrame: nil,
            preferredSize: size,
            previous: nil
        )
    }
    controller.setBackdropVisible(pinned, animated: false)
    controller.setCardFrame(frame)
    return controller
}

private func chrome(_ mode: ReaderChrome.Mode, app: String = "Safari", bundle: String = "com.apple.Safari") -> ReaderChrome {
    ReaderChrome(fontSize: FontSize(points: 64), mode: mode, appName: app, bundleIdentifier: bundle)
}

private let paragraph = String(
    repeating: "The quick brown fox jumps over the lazy dog, and the dog does not seem to mind at all. ",
    count: 12
)

#Preview("Label") {
    readerPreview(.text("Downloads", scrollToUTF16: nil), chrome: chrome(.pinned, app: "Finder", bundle: "com.apple.finder"))
}

#Preview("Long paragraph") {
    readerPreview(.text(paragraph, scrollToUTF16: nil), chrome: chrome(.pinned))
}

#Preview("Following") {
    readerPreview(
        .text(paragraph, scrollToUTF16: (paragraph as NSString).length / 2),
        chrome: chrome(.following)
    )
}

#Preview("Pinned") {
    readerPreview(
        .text("Your order has shipped and will arrive on Thursday.", scrollToUTF16: nil),
        chrome: chrome(.pinned, app: "Mail", bundle: "com.apple.mail")
    )
}

#Preview("No text here") {
    readerPreview(.nothing, chrome: chrome(.following))
}

#Preview("Hidden text") {
    readerPreview(.hidden, chrome: chrome(.pinned, app: "1Password", bundle: "com.1password.1password"))
}
