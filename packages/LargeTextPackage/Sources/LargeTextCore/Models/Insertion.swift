import Foundation

package enum InsertionFallbackReason: Equatable, Sendable {
    case permissionMissing
    case noEditableTarget
    case targetChanged
    case modifiersHeld
    /// ⌘, closed an editor with text in it: the text is copied so opening Settings doesn't lose it.
    case settingsOpened
}

package enum InsertionOutcome: Equatable, Sendable {
    /// `clipboardOverwritten` is true when `ClipboardRestorePolicy.none` is in effect.
    case inserted(clipboardOverwritten: Bool)
    case copiedToClipboard(InsertionFallbackReason)
}

package enum ClipboardRestorePolicy: Equatable, Codable, Sendable {
    case restore(maxBytes: Int)
    case none

    package static let `default` = ClipboardRestorePolicy.restore(maxBytes: 10 * 1024 * 1024)
}

package struct InsertionTiming: Equatable, Sendable {
    package var focusReturnDelay: Duration
    package var pollInterval: Duration
    package var maxModifierPolls: Int
    package var restoreDelay: Duration

    package init(focusReturnDelay: Duration, pollInterval: Duration, maxModifierPolls: Int, restoreDelay: Duration) {
        self.focusReturnDelay = focusReturnDelay
        self.pollInterval = pollInterval
        self.maxModifierPolls = maxModifierPolls
        self.restoreDelay = restoreDelay
    }

    /// `focusReturnDelay` is the starting value; spike 0a refines it.
    package static let `default` = InsertionTiming(
        focusReturnDelay: .milliseconds(50),
        pollInterval: .milliseconds(20),
        maxModifierPolls: 15,
        restoreDelay: .milliseconds(600)
    )
}

package struct PasteboardSnapshot: Equatable, Sendable {
    package struct Item: Equatable, Sendable {
        package var dataByType: [String: Data]
        package init(dataByType: [String: Data]) { self.dataByType = dataByType }
    }

    package var items: [Item]
    package var isComplete: Bool

    package init(items: [Item], isComplete: Bool) {
        self.items = items
        self.isComplete = isComplete
    }
}
