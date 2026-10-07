import ApplicationServices
import Testing
@testable import LargeTextPlatform

/// Drives the per-pid bookkeeping through the `setManualAccessibility` seam; never touches AX.
@Suite struct AXAppPreparerTests {
    final class SetterSpy {
        var pids: [pid_t] = []
        var result: AXError = .success

        func set(_ pid: pid_t) -> AXError {
            pids.append(pid)
            return result
        }
    }

    let spy = SetterSpy()

    func makePreparer(families: Set<AXAppFamily> = [.electron, .chromiumBrowser]) -> AXAppPreparer {
        AXAppPreparer(families: families, setManualAccessibility: spy.set)
    }

    @Test func preparesAnEligiblePidOnceAndAsksForARetry() {
        let preparer = makePreparer()

        let first = preparer.prepareIfNeeded(pid: 42, bundleIdentifier: "com.google.Chrome", family: .chromiumBrowser)
        let second = preparer.prepareIfNeeded(pid: 42, bundleIdentifier: "com.google.Chrome", family: .chromiumBrowser)

        #expect(first == .prepared)
        #expect(first.shouldRetry)
        #expect(second == .alreadyExamined)
        #expect(!second.shouldRetry)
        #expect(spy.pids == [42])
    }

    @Test func eachPidIsPreparedSeparately() {
        let preparer = makePreparer()

        preparer.prepareIfNeeded(pid: 1, bundleIdentifier: nil, family: .electron)
        preparer.prepareIfNeeded(pid: 2, bundleIdentifier: nil, family: .electron)

        #expect(spy.pids == [1, 2])
        #expect(preparer.examinedPIDs == [1, 2])
    }

    @Test func ineligibleFamilyIsNotPreparedAndNotReclassified() {
        let preparer = makePreparer()
        var classifications = 0
        func family() -> AXAppFamily {
            classifications += 1
            return .native
        }

        #expect(preparer.prepareIfNeeded(pid: 7, bundleIdentifier: "com.apple.Notes", family: family()) == .notApplicable)
        #expect(preparer.prepareIfNeeded(pid: 7, bundleIdentifier: "com.apple.Notes", family: family()) == .alreadyExamined)
        #expect(classifications == 1)
        #expect(spy.pids.isEmpty)
    }

    /// The editor's preparer keeps today's behaviour: Electron only.
    @Test func editorPreparerIgnoresChromium() {
        let preparer = makePreparer(families: [.electron])

        #expect(preparer.prepareIfNeeded(pid: 3, bundleIdentifier: "com.google.Chrome", family: .chromiumBrowser) == .notApplicable)
        #expect(preparer.prepareIfNeeded(pid: 4, bundleIdentifier: "com.tinyspeck.slackmacgap", family: .electron) == .prepared)
        #expect(spy.pids == [4])
    }

    @Test func failureIsReportedOnceWithoutRetry() {
        spy.result = .cannotComplete
        let preparer = makePreparer()

        let outcome = preparer.prepareIfNeeded(pid: 9, bundleIdentifier: nil, family: .electron)

        #expect(outcome == .failed(.cannotComplete))
        #expect(!outcome.shouldRetry)
        #expect(preparer.prepareIfNeeded(pid: 9, bundleIdentifier: nil, family: .electron) == .alreadyExamined)
        #expect(spy.pids == [9])
    }

    @Test func emptyHits() {
        #expect(AXAppPreparer.isEmptyHit(role: nil, childCount: nil))
        #expect(AXAppPreparer.isEmptyHit(role: "AXWebArea", childCount: 0))
        #expect(AXAppPreparer.isEmptyHit(role: "AXGroup", childCount: nil))
        #expect(!AXAppPreparer.isEmptyHit(role: "AXGroup", childCount: 3))
        #expect(!AXAppPreparer.isEmptyHit(role: "AXStaticText", childCount: 0))
    }

    @Test func retryDelayIs200Milliseconds() {
        #expect(AXAppPreparer.retryDelay == .milliseconds(200))
    }
}
