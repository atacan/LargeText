import AppKit
import Foundation
import LargeTextCore
import Testing
@testable import LargeTextUI

/// Creates real (never activated) panels on a fixed screen layout. Reduce Motion is forced on so no
/// animation has to complete.
@MainActor
@Suite("ReaderWindowController smoke", .enabled(if: !NSScreen.screens.isEmpty))
struct ReaderWindowControllerSmokeTests {
    private let screen = ScreenDescriptor(
        id: 1,
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)
    )
    private let text = ReaderContent.text("Your order has shipped.", scrollToUTF16: nil)

    private func makeController(pointer: CGPoint = CGPoint(x: 700, y: 200)) -> ReaderWindowController {
        _ = NSApplication.shared
        let screen = screen
        return ReaderWindowController(reduceMotion: { true }, screens: { [screen] }, mouseLocation: { pointer })
    }

    private func chrome(_ mode: ReaderChrome.Mode) -> ReaderChrome {
        ReaderChrome(
            fontSize: FontSize(points: 64),
            mode: mode,
            appName: "Safari",
            sourceFrame: CGRect(x: 600, y: 180, width: 300, height: 40)
        )
    }

    private func sample(_ point: CGPoint) -> PointerSample {
        PointerSample(appKit: point, global: CGPoint(x: point.x, y: 900 - point.y))
    }

    @Test func followingIsClickThroughNeverKeyAndSizedToTheCard() async throws {
        let reader = makeController()
        var received: [ReaderIntent] = []

        reader.present(sessionID: UUID(), content: text, chrome: chrome(.following)) { received.append($0) }
        let panel = try #require(reader.panel)
        let cardFrame = try #require(reader.cardFrame)

        #expect(!panel.allowsKey)
        #expect(!panel.canBecomeKey)
        #expect(!panel.isKeyWindow)
        #expect(panel.ignoresMouseEvents)
        #expect(panel.isVisible)
        #expect(panel.frame == cardFrame)
        #expect(panel.frame.height < screen.frame.height * 0.5)
        // The pointer is in the bottom half, so the card is at the top.
        #expect(cardFrame.minY > screen.visibleFrame.midY)
        #expect(reader.reader?.isBackdropVisible == false)

        await reader.dismiss()
        #expect(!panel.isVisible)
        #expect(received.isEmpty)
    }

    @Test func pointerAloneMovesTheCardWhenItReachesIt() async throws {
        let reader = makeController()
        reader.present(sessionID: UUID(), content: text, chrome: chrome(.following)) { _ in }
        let top = try #require(reader.cardFrame)

        // Past the middle but clear of the card: stays.
        reader.pointerMoved(sample(CGPoint(x: 700, y: top.minY - 100)))
        #expect(reader.cardFrame == top)

        // Onto the card, with no new content: flips to the bottom, and the panel goes with it.
        reader.pointerMoved(sample(CGPoint(x: 700, y: top.midY)))
        let bottom = try #require(reader.cardFrame)
        #expect(bottom.maxY < screen.visibleFrame.midY)
        #expect(reader.panel?.frame == bottom)

        await reader.dismiss()
    }

    @Test func pinExpandsToTheScreenWithoutMovingTheCard() async throws {
        let reader = makeController()
        reader.present(sessionID: UUID(), content: text, chrome: chrome(.following)) { _ in }
        let following = try #require(reader.cardFrame)

        reader.pin(content: .text("Your order has shipped. It arrives Thursday.", scrollToUTF16: nil), chrome: chrome(.pinned))
        let panel = try #require(reader.panel)
        let pinned = try #require(reader.cardFrame)

        #expect(panel.allowsKey)
        #expect(panel.canBecomeKey)
        #expect(!panel.ignoresMouseEvents)
        #expect(panel.frame == screen.frame)
        #expect(reader.reader?.isBackdropVisible == true)
        // Same origin and anchor edge (top half → top edge), same width.
        #expect(pinned.maxY == following.maxY)
        #expect(pinned.minX == following.minX)
        #expect(pinned.width == following.width)
        // The card sits at the same screen position inside the full-screen panel.
        #expect(reader.reader?.cardFrame == pinned.offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY))

        await reader.dismiss()
        #expect(!panel.isVisible)
    }

    @Test func directPinCentresOnTheScreen() async throws {
        let reader = makeController()
        reader.present(sessionID: UUID(), content: text, chrome: chrome(.pinned)) { _ in }
        let panel = try #require(reader.panel)
        let card = try #require(reader.cardFrame)

        #expect(panel.allowsKey)
        #expect(panel.frame == screen.frame)
        #expect(abs(card.midX - screen.visibleFrame.midX) <= 0.5)
        #expect(abs(card.midY - screen.visibleFrame.midY) <= 0.5)

        await reader.dismiss()
    }

    @Test func intentsAreTaggedAndStopAtDismiss() async throws {
        let reader = makeController()
        let sessionID = UUID()
        var received: [ReaderIntent] = []
        reader.present(sessionID: sessionID, content: text, chrome: chrome(.pinned)) { received.append($0) }
        let textView = try #require(reader.reader?.textView)

        textView.perform(.close)
        textView.perform(.zoom(.bigger))
        #expect(received == [
            ReaderIntent(sessionID: sessionID, kind: .close(.userCancelled)),
            ReaderIntent(sessionID: sessionID, kind: .zoom(.bigger)),
        ])

        await reader.dismiss()
        textView.perform(.close)
        #expect(received.count == 2)
    }

    @Test func followingIgnoresResignKey() async throws {
        let reader = makeController()
        var received: [ReaderIntent] = []
        reader.present(sessionID: UUID(), content: text, chrome: chrome(.following)) { received.append($0) }

        try #require(reader.panel).resignKey()
        #expect(received.isEmpty)

        await reader.dismiss()
    }

    @Test func placeholderContent() async throws {
        let reader = makeController()
        reader.present(sessionID: UUID(), content: .nothing, chrome: chrome(.following)) { _ in }
        let textView = try #require(reader.reader?.textView)
        #expect(textView.string == ReaderStrings.noText)
        #expect(!textView.isSelectable)

        reader.update(content: .hidden, chrome: chrome(.following))
        #expect(textView.string == ReaderStrings.hiddenText)

        reader.update(content: text, chrome: chrome(.following))
        #expect(textView.string == "Your order has shipped.")
        #expect(textView.isSelectable)
        #expect(!textView.isEditable)

        await reader.dismiss()
    }

    @Test func panelIsReusedAcrossSessions() async throws {
        let reader = makeController()
        reader.present(sessionID: UUID(), content: text, chrome: chrome(.pinned)) { _ in }
        let first = try #require(reader.panel)
        await reader.dismiss()

        reader.present(sessionID: UUID(), content: text, chrome: chrome(.following)) { _ in }
        #expect(reader.panel === first)
        // A new following session starts click-through and non-key again.
        #expect(!first.allowsKey)
        #expect(first.ignoresMouseEvents)
        #expect(first.frame == reader.cardFrame)
        await reader.dismiss()
    }

    @Test func dismissWithoutPresentReturns() async {
        let reader = makeController()
        await reader.dismiss()
        #expect(reader.panel == nil)
    }
}
