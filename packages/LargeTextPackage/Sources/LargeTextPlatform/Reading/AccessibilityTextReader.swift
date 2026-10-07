import ApplicationServices
import CoreGraphics
import Foundation
import LargeTextCore
import os

/// The live `TextReading` (§4.3, §4.4): hit test → denylist → stage 0 → `ReadPlan` loop → `ReadTextChooser`.
///
/// An actor on its own serial queue, so blocking AX calls never run on the main thread or the cooperative
/// pool, and the main thread stays free to answer a hit on our own windows. `AXUIElement` values never leave
/// it; only Sendable `PointerSample`, `ReadPolicy` and `ReadResult` cross the boundary.
///
/// Logging follows §4.10: roles, steps, lengths, durations, AX call counts and the bundle ID; never a string
/// from another app.
package actor AccessibilityTextReader: TextReading {
    private let queue = DispatchSerialQueue(label: "LargeText.reader.ax", qos: .userInteractive)
    private let hitTester = AXHitTester()
    /// The reader's own instance (§4.11); the focus capturer has another.
    private let preparer = AXAppPreparer(families: [.electron, .chromiumBrowser])

    package nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    /// Side-effect free: nothing touches AX until the first `read`.
    package init() {}

    package func read(at pointer: PointerSample, granularity: ReadGranularity, pid: Int32?, policy: ReadPolicy) async -> ReadResult {
        AXConfiguration.applyMessagingTimeoutIfNeeded()
        let calls = AXCallCounter()
        let start = ContinuousClock.now
        var report = ReadReport()
        let result: ReadResult
        do {
            result = try await extract(
                at: pointer,
                granularity: granularity,
                pid: pid,
                policy: policy,
                calls: calls,
                report: &report,
                mayRetry: true
            )
        } catch {
            report.abortedBy = error
            result = Self.result(for: error)
        }
        Logger.platform.info(
            """
            Read in \(AXReadStepRunner.milliseconds(since: start), format: .fixed(precision: 1), privacy: .public) ms, \
            \(calls.count) AX calls: app=\(report.bundleIdentifier ?? "nil", privacy: .public) \
            role=\(report.role ?? "nil", privacy: .public) subrole=\(report.subrole ?? "nil", privacy: .public) \
            steps=[\(report.steps.map { String(describing: $0) }.joined(separator: ", "), privacy: .public)] \
            hitError=\(report.hitError.map { String($0.rawValue) } ?? "none", privacy: .public) \
            retried=\(report.retried) cancelled=\(report.cancelled) \
            aborted=\(report.abortedBy.map { String(describing: $0) } ?? "no", privacy: .public) \
            result=\(Self.summary(of: result), privacy: .public)
            """
        )
        return result
    }

    // MARK: - Stages

    /// One attempt; after preparing an app whose tree was empty, calls itself once more with `mayRetry` false.
    private func extract(
        at pointer: PointerSample,
        granularity: ReadGranularity,
        pid: Int32?,
        policy: ReadPolicy,
        calls: AXCallCounter,
        report: inout ReadReport,
        mayRetry: Bool
    ) async throws(AXReadError) -> ReadResult {
        let target: AXHitTarget
        switch try hitTester.hitTest(at: pointer, pid: pid, calls: calls) {
        case .target(let hit):
            target = hit
        case .ownProcess:
            // The coordinator turns this into "no update" while following and `.nothing` on a tap (§4.2).
            return .ownWindow
        case .nothing(let error):
            report.hitError = error
            return .nothing
        }
        report.bundleIdentifier = target.bundleIdentifier
        // Before stage 0, so no string is ever fetched from a denylisted app (§3.3).
        if Self.isDenylisted(target, policy: policy) { return .hidden }

        // Built per read, so the primary-screen frame is current after a display change.
        let primaryScreenFrame = AXGeometry.primaryScreenFrame()
        let ax = AXAttributes(target.element, calls: calls)
        var candidates = try AXStageZeroReader(primaryScreenFrame: primaryScreenFrame).read(target, calls: calls)
        report.role = candidates.role
        report.subrole = candidates.subrole

        if mayRetry, try prepareAppIfEmpty(target, candidates: candidates, ax: ax) {
            // The tree builds asynchronously after `AXManualAccessibility` is set (§4.11).
            guard !Task.isCancelled else { return cancelled(&report) }
            try? await Task.sleep(for: AXAppPreparer.retryDelay)
            guard !Task.isCancelled else { return cancelled(&report) }
            report.retried = true
            return try await extract(
                at: pointer,
                granularity: granularity,
                pid: pid,
                policy: policy,
                calls: calls,
                report: &report,
                mayRetry: false
            )
        }

        let runner = AXReadStepRunner(policy: policy, primaryScreenFrame: primaryScreenFrame)
        while case let step = ReadPlan.next(after: candidates, granularity: granularity, policy: policy), step != .done {
            guard !Task.isCancelled else { return cancelled(&report) }
            report.steps.append(step)
            candidates = try runner.run(step, on: ax, pointer: pointer, candidates: candidates)
        }

        let result = ReadTextChooser.choose(
            from: candidates,
            granularity: granularity,
            policy: policy,
            appName: target.localizedName
        )
        return try highlightingUnit(of: result, candidates: candidates, ax: ax, primaryScreenFrame: primaryScreenFrame)
    }

    /// Sets `AXManualAccessibility` on a Chromium or Electron app whose hit was empty; `true` means "retry
    /// once". The child count is fetched only for a container hit in an app the preparer would still act on.
    private func prepareAppIfEmpty(_ target: AXHitTarget, candidates: ReadCandidates, ax: AXAttributes) throws(AXReadError) -> Bool {
        guard preparer.mayPrepare(pid: target.pid, family: target.family),
              AXAppPreparer.isEmptyHit(role: candidates.role, childCount: 0)
        else { return false }
        let childCount = try ax.count(kAXChildrenAttribute)
        guard AXAppPreparer.isEmptyHit(role: candidates.role, childCount: childCount) else { return false }
        return preparer.prepareIfNeeded(
            pid: target.pid,
            bundleIdentifier: target.bundleIdentifier,
            family: target.family
        ).shouldRetry
    }

    /// For a native unit, replaces the element frame with the unit's own bounds, so the highlight outlines
    /// the sentence or paragraph being read (§4.7). The chooser already segmented the text; the same pure
    /// `TextSegmenter` call on the window it kept gives the unit's element range. Bad bounds keep the element
    /// frame.
    private func highlightingUnit(
        of result: ReadResult,
        candidates: ReadCandidates,
        ax: AXAttributes,
        primaryScreenFrame: CGRect
    ) throws(AXReadError) -> ReadResult {
        guard case .text(var text) = result, text.source == .unit, let window = text.window,
              candidates.supportedParameterized.contains(kAXBoundsForRangeParameterizedAttribute),
              let unit = TextSegmenter.unit(text.granularity, in: window),
              let bounds = try AXTextRangeReader(primaryScreenFrame: primaryScreenFrame).bounds(forRange: unit.range, on: ax),
              !bounds.isEmpty
        else { return result }
        text.sourceFrame = bounds
        return .text(text)
    }

    private func cancelled(_ report: inout ReadReport) -> ReadResult {
        // The coordinator drops a cancelled read's result; the value only has to be cheap.
        report.cancelled = true
        return .nothing
    }

    // MARK: - Decisions (pure)

    /// The denylist check on what the hit test alone knows: pid and bundle ID. The rule itself is
    /// `ReadTextChooser.isHidden`, which repeats it on the final candidates as defence in depth.
    static func isDenylisted(_ target: AXHitTarget, policy: ReadPolicy) -> Bool {
        ReadTextChooser.isHidden(ReadCandidates(pid: target.pid, bundleIdentifier: target.bundleIdentifier), policy: policy)
    }

    /// `cannotComplete` (a busy or hung app, or the 0.1 s timeout) aborts the read with nothing to show;
    /// `apiDisabled` means trust is missing or was revoked.
    static func result(for error: AXReadError) -> ReadResult {
        switch error {
        case .cannotComplete: .nothing
        case .apiDisabled: .permissionMissing
        }
    }

    /// §4.10: the kind, source and length of the result; never its text.
    static func summary(of result: ReadResult) -> String {
        switch result {
        case .text(let text):
            "text(source=\(text.source), granularity=\(text.granularity), length=\(text.text.utf16.count), hasFrame=\(text.sourceFrame != nil))"
        case .hidden: "hidden"
        case .nothing: "nothing"
        case .ownWindow: "ownWindow"
        case .permissionMissing: "permissionMissing"
        }
    }
}

/// What one read did, for its single log line. Never holds a string from another app apart from the
/// bundle ID, role and subrole.
private struct ReadReport {
    var bundleIdentifier: String?
    var role: String?
    var subrole: String?
    /// In the order they ran.
    var steps: [ReadStep] = []
    var retried = false
    var cancelled = false
    var abortedBy: AXReadError?
    /// Why the hit test found no element.
    var hitError: AXError?
}
