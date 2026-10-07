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

        // 4. Text policy.
        let prepared = InsertionTextPolicy.prepare(text, for: target)

        // 5. Snapshot.
        let snapshot: PasteboardSnapshot?
        switch preferences.clipboardRestore {
        case .restore(let maxBytes):
            let taken = pasteboard.snapshot(maxBytes: maxBytes)
            if !taken.isComplete { Logger.core.info("Insertion: snapshot over budget; restore will be lossy") }
            snapshot = taken
        case .none:
            snapshot = nil
        }

        // 6. Write (transient, current host only).
        let writtenChangeCount = pasteboard.write(prepared, transient: true)

        // 7–8. Paste, then optionally submit.
        keystrokes.send(.paste)
        if mode == .insertAndSubmit { keystrokes.send(.returnKey) }
        Logger.core.info(
            "Insertion: pasted (\(String(describing: mode))) after \(start.duration(to: clock.now)), modifier polls \(polls)"
        )

        // 9. Return; restore in a tail task.
        guard let snapshot else {
            pendingRestore = nil
            return .inserted(clipboardOverwritten: true)
        }
        pendingRestore = Task { [pasteboard, sleeper, timing] in
            try? await sleeper.sleep(for: timing.restoreDelay)
            guard pasteboard.changeCount == writtenChangeCount else {
                Logger.core.info("Insertion: restore skipped; pasteboard changed since our write")
                return
            }
            pasteboard.restore(snapshot)
            Logger.core.info("Insertion: clipboard restored (complete: \(snapshot.isComplete))")
        }
        return .inserted(clipboardOverwritten: false)
    }
}
