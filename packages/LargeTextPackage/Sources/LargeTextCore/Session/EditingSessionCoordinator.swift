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
    /// The reader shortcut is ignored unless this is true (§4.8).
    package var isIdle: Bool { phase == .idle }
    /// Called after ⌘, has closed the editor; Kit opens Settings (`AppController.openSettings()`).
    package var onOpenSettings: (@MainActor () -> Void)?

    private let dependencies: CoreDependencies
    private var session: EditingSession?
    /// The chrome currently shown, so zoom updates re-send all of it.
    private var chrome: OverlayChrome?
    /// Last cancelled non-blank text, in memory only.
    private var draft: String?
    /// `closeForSettings()` callers waiting for a closing session to finish; resumed in `finish`.
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

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
        case .openSettings:
            await closeForSettings(session)
            onOpenSettings?()
        }
    }

    /// Closes the editor before Settings opens, from ⌘, or from Kit (the status menu while the editor is
    /// open). Text in the editor is copied, so it isn't lost behind the window. Does nothing when idle. A
    /// session that is already closing (a ⌘↩ commit still inserting, say) is awaited, so Settings doesn't
    /// activate LargeText while the paste is still on its way to the target app.
    package func closeForSettings() async {
        switch phase {
        case .idle:
            return
        case .editing(let id):
            guard let session, session.id == id else { return }
            await closeForSettings(session)
        case .closing:
            await waitUntilIdle()
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
        let hints = TargetHints(willCopyToClipboard: route != .paste)
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

        // Whitespace is the user's text too; only an empty editor means "nothing to insert".
        guard !text.isEmpty else {
            Logger.core.info("Session \(session.id): empty commit")
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
        draft = text.isEmpty ? nil : text
        Logger.core.info("Session \(session.id): cancelled (\(String(describing: reason)))")
        finish(session)
    }

    /// Like `cancel`, so the text is also kept as the draft, but non-empty text is copied as well, with the
    /// "Copied — press ⌘V" HUD (Settings plan §3.5).
    private func closeForSettings(_ session: EditingSession) async {
        phase = .closing(sessionID: session.id)
        let text = await dependencies.overlay.dismiss()
        draft = text.isEmpty ? nil : text
        if !text.isEmpty {
            _ = ClipboardWriter(pasteboard: dependencies.pasteboard).copy(text, reason: .settingsOpened)
            dependencies.notices.show(.copiedToClipboard(.settingsOpened))
        }
        Logger.core.info("Session \(session.id): closed for Settings (\(text.isEmpty ? "empty" : "copied", privacy: .public))")
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
        let waiters = idleWaiters
        idleWaiters = []
        waiters.forEach { $0.resume() }
    }

    private func waitUntilIdle() async {
        guard phase != .idle else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }
}
