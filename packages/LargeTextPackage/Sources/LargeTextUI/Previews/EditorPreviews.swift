import AppKit
import LargeTextCore

// Fast visual loop for the overlay (select the package scheme in Xcode). Keys work in the live preview;
// commit / cancel / zoom are no-ops because no window controller is attached.

@MainActor
private func editorPreview(_ text: String, chrome: OverlayChrome) -> EditorViewController {
    let controller = EditorViewController()
    controller.render(chrome)
    controller.setInitialText(text)
    return controller
}

private let safari = OverlayChrome(
    fontSize: FontSize(points: 64),
    targetName: "Safari",
    targetBundleIdentifier: "com.apple.Safari"
)

#Preview("Empty") {
    editorPreview("", chrome: OverlayChrome(fontSize: FontSize(points: 64)))
}

#Preview("Prefilled") {
    editorPreview("https://www.apple.com", chrome: safari)
}

#Preview("Long text") {
    editorPreview(
        String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 30),
        chrome: OverlayChrome(fontSize: FontSize(points: 64), targetName: "Notes", targetBundleIdentifier: "com.apple.Notes")
    )
}

#Preview("Flattens newlines") {
    editorPreview(
        "git status\ngit diff",
        chrome: OverlayChrome(
            fontSize: FontSize(points: 64),
            targetName: "Terminal",
            targetBundleIdentifier: "com.apple.Terminal",
            hints: TargetHints(flattensNewlines: true)
        )
    )
}

#Preview("Will copy") {
    editorPreview(
        "Hello from across the room",
        chrome: OverlayChrome(
            fontSize: FontSize(points: 96),
            hints: TargetHints(willCopyToClipboard: true)
        )
    )
}
