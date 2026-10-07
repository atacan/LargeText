import AppKit
import ApplicationServices
import LargeTextCore

/// The element under the pointer in another app. Not `Sendable`: it never leaves the reader's actor.
package struct AXHitTarget {
    package let element: AXUIElement
    package let pid: pid_t
    package let bundleIdentifier: String?
    package let family: AXAppFamily
}

package enum AXHitResult {
    case target(AXHitTarget)
    /// The hit landed on one of our own windows (the reader card or highlight). Until spike R4 decides,
    /// this is "no update" while following and `.nothing` on a tap (§4.2).
    case ownProcess
    /// No element at the point, or the owner couldn't be resolved. Carries the AX error code for the log.
    case nothing(AXError)
}

/// Finds the element under the pointer (§4.2).
///
/// System-wide first: `AXUIElementCopyElementAtPosition` on the system-wide element is expected to follow
/// the window server's mouse routing and skip our click-through panels. Whether it really does is spike R4;
/// the `CGWindowList`-based `WindowHitTester` fallback is only built if R4 requires it, so there is none yet.
///
/// Must run off the main thread: a hit on our own window is answered by our main thread.
package struct AXHitTester {
    private let ownPID: pid_t

    package init(ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) {
        self.ownPID = ownPID
    }

    /// - Parameter pid: when set, an app-scoped hit test on that application instead of the system-wide one
    ///   (e.g. a re-read of the frozen app on pin).
    package func hitTest(at pointer: PointerSample, pid: pid_t? = nil, calls: AXCallCounter) throws(AXReadError) -> AXHitResult {
        let root = pid.map(AXUIElementCreateApplication) ?? AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(root, Float(pointer.global.x), Float(pointer.global.y), &element)
        calls.record()
        guard try AXReadError.check(error), let element else { return .nothing(error) }

        var owner: pid_t = 0
        let pidError = AXUIElementGetPid(element, &owner)
        guard pidError == .success else { return .nothing(pidError) }
        guard owner != ownPID else { return .ownProcess }

        let app = NSRunningApplication(processIdentifier: owner)
        let bundleIdentifier = app?.bundleIdentifier
        return .target(AXHitTarget(
            element: element,
            pid: owner,
            bundleIdentifier: bundleIdentifier,
            family: AXAppFamily.classify(bundleIdentifier: bundleIdentifier, bundleURL: app?.bundleURL)
        ))
    }
}
