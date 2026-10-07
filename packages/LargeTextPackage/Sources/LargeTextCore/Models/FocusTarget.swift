import CoreGraphics
import Foundation

package struct TargetApplication: Equatable, Sendable {
    package let processIdentifier: Int32
    package let bundleIdentifier: String?
    package let localizedName: String

    package init(processIdentifier: Int32, bundleIdentifier: String?, localizedName: String) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
    }
}

package enum ElementKind: Equatable, Sendable {
    case singleLineText
    case multiLineText
    case secureText
    case notEditable
}

/// Opaque handle to the focused element (an `AXUIElement` in production). Logging only in v1.
package struct ElementHandle {
    package let raw: AnyObject
    package init(raw: AnyObject) { self.raw = raw }
}

/// What had keyboard focus when the hotkey was pressed. Never leaves the main actor.
package struct FocusTarget {
    /// `nil` when LargeText itself was frontmost.
    package let application: TargetApplication?
    package let element: ElementHandle?
    /// `nil` = unknown → still paste.
    package let elementKind: ElementKind?
    package let selectedText: String?
    /// Element frame, else focused-window frame; AppKit global coordinates.
    package let frame: CGRect?

    package init(
        application: TargetApplication?,
        element: ElementHandle? = nil,
        elementKind: ElementKind? = nil,
        selectedText: String? = nil,
        frame: CGRect? = nil
    ) {
        self.application = application
        self.element = element
        self.elementKind = elementKind
        self.selectedText = selectedText
        self.frame = frame
    }
}
