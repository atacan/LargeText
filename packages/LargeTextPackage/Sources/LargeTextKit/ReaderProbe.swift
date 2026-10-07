import ApplicationServices
import Foundation
import LargeTextCore
import LargeTextPlatform
import os

/// The driver of the `reader-probe` scenario (§5.4), the harness for spikes R2–R6 and R8.
///
/// Once per interval it hit-tests the point under the pointer, runs stage 0 and logs the attribute names,
/// the supported parameterized attributes and text lengths. Under the §4.10 rule it never logs a string
/// value. It knows nothing of the reading coordinator; `AppController` owns it.
@MainActor
package final class ReaderProbe {
    private let pointer: any PointerTracking
    private let interval: Duration
    private let worker = ReaderProbeWorker()
    private var task: Task<Void, Never>?

    package init(pointer: any PointerTracking = SystemPointerTracker(), interval: Duration = .seconds(1)) {
        self.pointer = pointer
        self.interval = interval
    }

    /// Idempotent.
    package func start() {
        guard task == nil else { return }
        Logger.kit.info("Reader probe started")
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await worker.probe(at: pointer.current)
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Idempotent. A probe already running on the worker still finishes and logs.
    package func stop() {
        guard let task else { return }
        task.cancel()
        self.task = nil
        Logger.kit.info("Reader probe stopped")
    }
}

/// Runs the probe's AX calls on their own serial queue, like the live reader (§4.4): never on the main
/// thread, which must stay free to answer a hit on our own windows.
private actor ReaderProbeWorker {
    private let queue = DispatchSerialQueue(label: "LargeText.reader.probe", qos: .utility)
    private let hitTester = AXHitTester()

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    func probe(at pointer: PointerSample) {
        guard AXIsProcessTrusted() else {
            Logger.kit.notice("Probe: Accessibility not trusted")
            return
        }
        AXConfiguration.applyMessagingTimeoutIfNeeded()
        let calls = AXCallCounter()
        let start = ContinuousClock.now
        do {
            switch try hitTester.hitTest(at: pointer, calls: calls) {
            case .ownProcess:
                Logger.kit.info("Probe: own process under the pointer")
            case .nothing(let error):
                Logger.kit.info("Probe: no element (AX error \(error.rawValue))")
            case .target(let target):
                // Built per probe, so the primary-screen frame is current after a display change.
                let candidates = try AXStageZeroReader().read(target, calls: calls)
                let attributeNames = try AXAttributes(target.element, calls: calls).attributeNames()
                log(candidates, family: target.family, attributeNames: attributeNames, calls: calls.count, since: start)
            }
        } catch {
            Logger.kit.notice("Probe aborted: \(String(describing: error), privacy: .public) after \(calls.count) AX calls")
        }
    }

    /// §4.10: names, roles, lengths, counts and the bundle ID; never a string value.
    private func log(
        _ candidates: ReadCandidates,
        family: AXAppFamily,
        attributeNames: [String],
        calls: Int,
        since start: ContinuousClock.Instant
    ) {
        let elapsed = ContinuousClock.now - start
        let milliseconds = Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
        let lengths: [(String, String?)] = [
            ("title", candidates.title),
            ("description", candidates.description),
            ("help", candidates.help),
            ("placeholder", candidates.placeholder),
        ]
        let presentStageZero = lengths.compactMap { name, text in text.map { "\(name)=\($0.utf16.count)" } }
        Logger.kit.info(
            """
            Probe in \(milliseconds, format: .fixed(precision: 1), privacy: .public) ms, \(calls) AX calls: \
            app=\(candidates.bundleIdentifier ?? "nil", privacy: .public) pid=\(candidates.pid) \
            family=\(String(describing: family), privacy: .public) \
            role=\(candidates.role ?? "nil", privacy: .public) subrole=\(candidates.subrole ?? "nil", privacy: .public) \
            lengths=[\(presentStageZero.joined(separator: ", "), privacy: .public)] \
            characterCount=\(candidates.characterCount.map(String.init) ?? "nil", privacy: .public) \
            hasFrame=\(candidates.elementFrame != nil) webArea=\(candidates.webArea)
            """
        )
        Logger.kit.info("Probe attributes: \(attributeNames.sorted().joined(separator: ", "), privacy: .public)")
        Logger.kit.info(
            "Probe parameterized: \(candidates.supportedParameterized.sorted().joined(separator: ", "), privacy: .public)"
        )
    }
}
