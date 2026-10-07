import AppKit
import Foundation
import LargeTextCore
import Testing
@testable import LargeTextUI

/// Creates a real (never activated) panel. Reduce Motion is forced on so no animation has to complete.
@MainActor
@Suite("OverlayWindowController smoke", .enabled(if: !NSScreen.screens.isEmpty))
struct OverlayWindowControllerSmokeTests {
    private let chrome = OverlayChrome(fontSize: FontSize(points: 64), targetName: "Safari")

    @Test func presentThenDismissReturnsTheText() async {
        _ = NSApplication.shared
        let overlay = OverlayWindowController(reduceMotion: { true })
        var received: [OverlayIntent] = []

        overlay.present(sessionID: UUID(), initialText: "hello", chrome: chrome) { received.append($0) }
        overlay.update(OverlayChrome(fontSize: FontSize(points: 96)))
        let text = await overlay.dismiss()

        #expect(text == "hello")
        // Our own orderOut never produces an intent.
        #expect(received.isEmpty)
    }

    @Test func typedWhitespaceAndLineBreaksSurviveDismiss() async throws {
        _ = NSApplication.shared
        let overlay = OverlayWindowController(reduceMotion: { true })

        overlay.present(sessionID: UUID(), initialText: "", chrome: chrome) { _ in }
        let textView = try #require(overlay.editor?.textView)
        textView.insertText("  hello", replacementRange: textView.selectedRange())
        textView.insertNewlineIgnoringFieldEditor(nil)
        textView.insertText("\tworld ", replacementRange: textView.selectedRange())

        #expect(await overlay.dismiss() == "  hello\n\tworld ")
    }

    @Test func panelIsReusedAndTextIsReplacedPerSession() async {
        _ = NSApplication.shared
        let overlay = OverlayWindowController(reduceMotion: { true })

        overlay.present(sessionID: UUID(), initialText: "first", chrome: chrome) { _ in }
        #expect(await overlay.dismiss() == "first")

        overlay.present(sessionID: UUID(), initialText: "", chrome: chrome) { _ in }
        #expect(await overlay.dismiss() == "")
    }

    @Test func dismissWithoutPresentReturnsEmpty() async {
        let overlay = OverlayWindowController(reduceMotion: { true })
        #expect(await overlay.dismiss() == "")
    }

    @Test func editorSelectsInitialTextAndForwardsIntents() {
        let editor = EditorViewController()
        var kinds: [OverlayIntent.Kind] = []
        editor.onIntent = { kinds.append($0) }
        editor.render(chrome)
        editor.setInitialText("https://www.apple.com")

        #expect(editor.textView.selectedRange() == NSRange(location: 0, length: 21))
        editor.textView.onAction?(.commit(.insertAndSubmit))
        editor.textView.onAction?(.cancel)
        editor.textView.onAction?(.zoom(.bigger))
        #expect(kinds == [.commit(.insertAndSubmit), .cancel(.userCancelled), .zoom(.bigger)])
    }
}
