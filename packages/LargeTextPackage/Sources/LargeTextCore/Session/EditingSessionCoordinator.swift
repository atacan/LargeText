import Foundation
import os

/// Owns the editing session (§3.5). Every entry point sets `phase` synchronously before its first `await`,
/// so a second main-actor task queued behind the first always sees `closing`.
@MainActor
package final class EditingSessionCoordinator {
    package enum Phase: Equatable, Sendable {
        case idle
        case editing(sessionID: UUID)
        case closing(sessionID: UUID)
    }

    package private(set) var phase: Phase = .idle

    private let dependencies: CoreDependencies
    private var session: EditingSession?
    /// The chrome currently shown, so zoom updates re-send all of it.
    private var chrome: OverlayChrome?
    /// Last cancelled non-blank text, in memory only.
    private var draft: String?

    package init(dependencies: CoreDependencies) {
        self.dependencies = dependencies
    }

    /// Hotkey, status menu and present-on-launch. Opens when idle, commits (`.insert`) when editing.
    package func toggle() async {
        switch phase {
        case .idle:
            open()
        case .editing(let id):
            guard let session, session.id == id else { return }
            await commit(session, mode: .insert)
        case .closing(let id):
            Logger.core.debug("Session \(id): toggle() ignored while closing")
        }
    }

    package func handle(_ intent: OverlayIntent) async {
        guard case .editing(let id) = phase, id == intent.sessionID, let session else {
            Logger.core.debug("Intent \(String(describing: intent.kind)) for \(intent.sessionID) ignored in \(String(describing: self.phase))")
            return
        }
        switch intent.kind {
        case .commit(let mode):
            await commit(session, mode: mode)
        case .cancel(let reason):
            await cancel(session, reason: reason)
        case .zoom(let step):
            zoom(step)
        }
    }

    // MARK: - Transitions

    private func open() {
        let clock = ContinuousClock()
        let start = clock.now
        let target = dependencies.focus.captureFocus()
        Logger.core.info("Focus captured in \(start.duration(to: clock.now))")

        guard target.elementKind != .secureText else {
            dependencies.notices.show(.secureFieldUnsupported)
            return
        }

        let route = InsertionRoute.decide(target: target, permissions: dependencies.permissions.current)
        let hints = TargetHints(
            willCopyToClipboard: route != .paste,
            // Copy-only exits put the text on the clipboard unchanged, so flattening only applies to `.paste`.
            flattensNewlines: route == .paste && InsertionTextPolicy.flattensNewlines(for: target)
        )
        let chrome = OverlayChrome(
            fontSize: FontSizePolicy.clamp(dependencies.preferences.fontSize),
            targetName: target.application?.localizedName,
            targetBundleIdentifier: target.application?.bundleIdentifier,
            targetFrame: target.frame,
            hints: hints
        )
        let selection = target.selectedText.flatMap { $0.isEmpty ? nil : $0 }
        let session = EditingSession(target: target)

        self.session = session
        self.chrome = chrome
        phase = .editing(sessionID: session.id)
        Logger.core.info("Session \(session.id): editing (route \(String(describing: route)))")

        dependencies.overlay.present(
            sessionID: session.id,
            initialText: selection ?? draft ?? "",
            chrome: chrome,
            intents: { [weak self] intent in
                Task { await self?.handle(intent) }
            }
        )
    }

    private func commit(_ session: EditingSession, mode: CommitMode) async {
        phase = .closing(sessionID: session.id)
        let text = await dependencies.overlay.dismiss()
        defer { finish(session) }

        guard !text.isBlank else {
            Logger.core.info("Session \(session.id): blank commit")
            return
        }
        let outcome = await dependencies.inserter.insert(text, into: session.target, mode: mode)
        Logger.core.info("Session \(session.id): \(String(describing: outcome))")
        switch outcome {
        case .copiedToClipboard(let reason):
            dependencies.notices.show(.copiedToClipboard(reason))
        case .inserted(clipboardOverwritten: true):
            dependencies.notices.show(.clipboardReplaced)
        case .inserted(clipboardOverwritten: false):
            break
        }
        draft = nil
    }

    private func cancel(_ session: EditingSession, reason: CancelReason) async {
        phase = .closing(sessionID: session.id)
        let text = await dependencies.overlay.dismiss()
        draft = text.isBlank ? nil : text
        Logger.core.info("Session \(session.id): cancelled (\(String(describing: reason)))")
        finish(session)
    }

    private func zoom(_ step: ZoomStep) {
        guard var chrome else { return }
        chrome.fontSize = FontSizePolicy.apply(step, to: chrome.fontSize)
        dependencies.preferences.fontSize = chrome.fontSize
        self.chrome = chrome
        dependencies.overlay.update(chrome)
    }

    private func finish(_ session: EditingSession) {
        guard phase == .closing(sessionID: session.id) else { return }
        self.session = nil
        chrome = nil
        phase = .idle
    }
}

private extension String {
    var isBlank: Bool { allSatisfy(\.isWhitespace) }
}
