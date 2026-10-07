import AppKit
import ApplicationServices
import LargeTextCore
import os

/// Captures what had keyboard focus at hotkey time (§2.4). Best effort: without Accessibility trust,
/// only the frontmost application is known (`elementKind == nil`, which still pastes).
@MainActor
package final class AccessibilityFocusCapturer: FocusCapturing {
    static let batchAttributes: [String] = [
        kAXRoleAttribute,
        kAXSubroleAttribute,
        kAXSelectedTextAttribute,
        kAXPositionAttribute,
        kAXSizeAttribute,
    ]

    /// Spike 0j: Electron only exposes focus and selection after a client sets `AXManualAccessibility`. The
    /// editor prepares Electron apps only, on every capture; the reader owns its own preparer (§4.11).
    private let appPreparer = AXAppPreparer(families: [.electron])

    package init() {}

    package func captureFocus() -> FocusTarget {
        let start = ContinuousClock.now
        let target = makeTarget()
        let elapsed = ContinuousClock.now - start
        let milliseconds = Double(elapsed.components.seconds) * 1_000
            + Double(elapsed.components.attoseconds) / 1e15
        Logger.platform.info(
            """
            Focus captured in \(milliseconds, format: .fixed(precision: 1), privacy: .public) ms: \
            app=\(target.application?.bundleIdentifier ?? "nil", privacy: .public) \
            kind=\(String(describing: target.elementKind), privacy: .public) \
            hasSelection=\(target.selectedText != nil) hasFrame=\(target.frame != nil)
            """
        )
        return target
    }

    package var keyboardFocusProcessIdentifier: Int32? {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard AXIsProcessTrusted() else { return frontmostPID }
        AXConfiguration.applyMessagingTimeoutIfNeeded()
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            kAXFocusedApplicationAttribute as CFString,
            &value
        )
        guard error == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            Logger.platform.notice("kAXFocusedApplicationAttribute unavailable (\(error.rawValue)); using frontmost pid")
            return frontmostPID
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(value as! AXUIElement, &pid) == .success else { return frontmostPID }
        return pid
    }

    // MARK: - Steps

    private func makeTarget() -> FocusTarget {
        // Step 1: frontmost application.
        guard let app = NSWorkspace.shared.frontmostApplication else {
            Logger.platform.notice("No frontmost application")
            return FocusTarget(application: nil)
        }
        // AX calls into our own process would block our main thread until the timeout.
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return FocusTarget(application: nil)
        }
        let application = TargetApplication(
            processIdentifier: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier,
            localizedName: app.localizedName ?? app.bundleIdentifier ?? "Unknown App"
        )
        guard AXIsProcessTrusted() else {
            return FocusTarget(application: application)
        }

        // Step 2: global AX timeout, so a hung target cannot block the main thread for long.
        AXConfiguration.applyMessagingTimeoutIfNeeded()

        // Step 3: focused element (and focused window as frame fallback).
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        // Electron builds the tree asynchronously, so the very first capture may still be empty (unknown →
        // still pastes).
        appPreparer.prepareIfNeeded(
            pid: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier,
            family: AXAppFamily.classify(bundleIdentifier: app.bundleIdentifier, bundleURL: app.bundleURL)
        )
        guard let element = Self.copyElement(appElement, attribute: kAXFocusedUIElementAttribute) else {
            return FocusTarget(application: application, frame: focusedWindowFrame(of: appElement))
        }

        // Step 4: one batched read.
        var values: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(
            element,
            Self.batchAttributes as CFArray,
            AXCopyMultipleAttributeOptions(rawValue: 0),
            &values
        )
        if error != .success {
            Logger.platform.notice("Batched AX read failed (\(error.rawValue))")
        }
        let batch = AXBatchResult(attributes: Self.batchAttributes, array: values)

        // Step 5: frame, else the focused window's frame.
        let frame = Self.appKitFrame(position: batch.point(for: kAXPositionAttribute),
                                     size: batch.size(for: kAXSizeAttribute))
            ?? focusedWindowFrame(of: appElement)
        let selectedText = batch.string(for: kAXSelectedTextAttribute).flatMap { $0.isEmpty ? nil : $0 }

        return FocusTarget(
            application: application,
            element: ElementHandle(raw: element),
            elementKind: ElementKind.classify(
                role: batch.string(for: kAXRoleAttribute),
                subrole: batch.string(for: kAXSubroleAttribute)
            ),
            selectedText: selectedText,
            frame: frame
        )
    }

    private func focusedWindowFrame(of appElement: AXUIElement) -> CGRect? {
        guard let window = Self.copyElement(appElement, attribute: kAXFocusedWindowAttribute) else { return nil }
        let attributes = [kAXPositionAttribute, kAXSizeAttribute]
        var values: CFArray?
        _ = AXUIElementCopyMultipleAttributeValues(
            window,
            attributes as CFArray,
            AXCopyMultipleAttributeOptions(rawValue: 0),
            &values
        )
        let batch = AXBatchResult(attributes: attributes, array: values)
        return Self.appKitFrame(position: batch.point(for: kAXPositionAttribute),
                                size: batch.size(for: kAXSizeAttribute))
    }

    private static func appKitFrame(position: CGPoint?, size: CGSize?) -> CGRect? {
        guard let position, let size, let primary = NSScreen.screens.first else { return nil }
        return AXGeometry.appKitRect(axPosition: position, axSize: size, primaryScreenFrame: primary.frame)
    }

    private static func copyElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
