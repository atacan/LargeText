import LargeTextCore

/// What the HUD shows for a `Notice`. Pure.
package struct NoticeContent: Equatable, Sendable {
    package var title: String
    package var subtitle: String?

    package init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    package init(_ notice: Notice) {
        switch notice {
        case .copiedToClipboard(let reason):
            self.init(title: "Copied — press ⌘V", subtitle: Self.subtitle(for: reason))
        case .clipboardReplaced:
            self.init(title: "Inserted — your clipboard now contains this text")
        case .secureFieldUnsupported:
            self.init(title: "Password fields aren't supported")
        case .hotkeyUnavailable(let combo):
            self.init(
                title: "Shortcut \(KeyComboFormatter.string(for: combo)) unavailable",
                subtitle: "Another app may be using it"
            )
        case .nothingToRead:
            self.init(title: "No readable text under the pointer")
        case .readerNeedsAccessibility:
            self.init(title: "Allow Accessibility to read text", subtitle: "Choose Grant Access… in the LargeText menu")
        case .readerMenuHint(let combo):
            self.init(title: "Point at text and press \(KeyComboFormatter.string(for: combo))")
        }
    }

    private static func subtitle(for reason: InsertionFallbackReason) -> String {
        switch reason {
        case .permissionMissing: "Accessibility permission is missing"
        case .noEditableTarget: "No text field was focused"
        case .targetChanged: "The app changed before inserting"
        case .modifiersHeld: "Keys were still held down"
        }
    }
}
