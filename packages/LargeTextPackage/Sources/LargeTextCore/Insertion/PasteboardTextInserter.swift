import Foundation
import os

/// The only live `TextInserting`: pasteboard + synthesized ⌘V, with copy-only fallbacks (§2.5).
@MainActor
package final class PasteboardTextInserter: TextInserting {
    private let permissions: any PermissionsProviding
    private let pasteboard: any PasteboardClient
    private let keystrokes: any KeystrokeSending
    private let focus: any FocusCapturing
    private let preferences: any PreferencesStore
    private let sleeper: any Sleeper
    private let timing: InsertionTiming

    /// The conditional clipboard restore of the most recent paste. Tests `await pendingRestore?.value`.
    package private(set) var pendingRestore: Task<Void, Never>?
    /// The snapshot `pendingRestore` will put back, and the `changeCount` our write produced.
    private var inFlight: (snapshot: PasteboardSnapshot, writtenChangeCount: Int)?

    package init(
        permissions: any PermissionsProviding,
        pasteboard: any PasteboardClient,
        keystrokes: any KeystrokeSending,
        focus: any FocusCapturing,
        preferences: any PreferencesStore,
        sleeper: any Sleeper,
        timing: InsertionTiming = .default
    ) {
        self.permissions = permissions
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.focus = focus
        self.preferences = preferences
        self.sleeper = sleeper
        self.timing = timing
    }

    package func insert(_ text: String, into target: FocusTarget, mode: CommitMode) async -> InsertionOutcome {
        let clock = ContinuousClock()
        let start = clock.now
        let clipboard = ClipboardWriter(pasteboard: pasteboard)

        // 1. Route.
        let route = InsertionRoute.decide(target: target, permissions: permissions.current)
        guard route == .paste, let application = target.application else {
            if case .copyOnly(let reason) = route { return clipboard.copy(text, reason: reason) }
            return clipboard.copy(text, reason: .noEditableTarget)
        }

        // 2. Focus-return guard (application pid only; element identity is not comparable across AX wrappers).
        try? await sleeper.sleep(for: timing.focusReturnDelay)
        let focusedPID = focus.keyboardFocusProcessIdentifier
        let focusWait = start.duration(to: clock.now)
        guard focusedPID == application.processIdentifier else {
            Logger.core.info(
                "Insertion: focus guard failed after \(focusWait): expected pid \(application.processIdentifier), got \(focusedPID.map(String.init) ?? "nil")"
            )
            return clipboard.copy(text, reason: .targetChanged)
        }
        Logger.core.debug("Insertion: focus returned to pid \(application.processIdentifier) after \(focusWait)")

        // 3. Wait for modifiers to be released, bounded by a poll count (never by wall-clock time).
        var polls = 0
        while !keystrokes.pressedModifiers.isEmpty {
            guard polls < timing.maxModifierPolls else {
                Logger.core.info("Insertion: modifiers still held after \(polls) polls")
                return clipboard.copy(text, reason: .modifiersHeld)
            }
            polls += 1
            try? await sleeper.sleep(for: timing.pollInterval)
        }

        // 4. The text is pasted exactly as typed (whitespace and line breaks included);
        //    the target decides how to handle it.

        // 5. Snapshot.
        let snapshot: PasteboardSnapshot?
        switch preferences.clipboardRestore {
        case .restore(let maxBytes):
            if let inFlight, pasteboard.changeCount == inFlight.writtenChangeCount {
                // A previous paste's restore hasn't run yet, so the pasteboard still holds our own text.
                // Reuse its snapshot; snapshotting now would make our text the thing that gets "restored".
                pendingRestore?.cancel()
                snapshot = inFlight.snapshot
            } else {
                let taken = pasteboard.snapshot(maxBytes: maxBytes)
                if !taken.isComplete { Logger.core.info("Insertion: snapshot over budget; restore will be lossy") }
                snapshot = taken
            }
        case .none:
            snapshot = nil
        }

        // 6. Write (transient, current host only).
        let writtenChangeCount = pasteboard.write(text, transient: true)

        // 7–8. Paste, then optionally submit.
        keystrokes.send(.paste)
        if mode == .insertAndSubmit { keystrokes.send(.returnKey) }
        Logger.core.info(
            "Insertion: pasted (\(String(describing: mode))) after \(start.duration(to: clock.now)), modifier polls \(polls)"
        )

        // 9. Return; restore in a tail task.
        guard let snapshot else {
            pendingRestore?.cancel()
            pendingRestore = nil
            inFlight = nil
            return .inserted(clipboardOverwritten: true)
        }
        inFlight = (snapshot, writtenChangeCount)
        pendingRestore = Task { [sleeper, timing] in
            try? await sleeper.sleep(for: timing.restoreDelay)
            guard !Task.isCancelled else { return }
            self.restoreIfUnchanged()
        }
        return .inserted(clipboardOverwritten: false)
    }

    /// Restores right away instead of waiting for `restoreDelay`, e.g. when the app quits.
    package func flushPendingRestore() {
        pendingRestore?.cancel()
        pendingRestore = nil
        restoreIfUnchanged()
    }

    private func restoreIfUnchanged() {
        guard let inFlight else { return }
        self.inFlight = nil
        guard pasteboard.changeCount == inFlight.writtenChangeCount else {
            Logger.core.info("Insertion: restore skipped; pasteboard changed since our write")
            return
        }
        pasteboard.restore(inFlight.snapshot)
        Logger.core.info("Insertion: clipboard restored (complete: \(inFlight.snapshot.isComplete))")
    }
}
