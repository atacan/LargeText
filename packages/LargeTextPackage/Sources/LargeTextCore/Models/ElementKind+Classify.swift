import Foundation

extension ElementKind {
    /// Roles that are definitely not text input. Only these become `.notEditable` (copy-only); anything
    /// ambiguous (e.g. `AXGroup`, `AXWebArea` used by contenteditable editors) stays unknown and is pasted.
    package static let notTextRoles: Set<String> = [
        "AXButton",
        "AXCheckBox",
        "AXRadioButton",
        "AXPopUpButton",
        "AXMenuButton",
        "AXDisclosureTriangle",
        "AXList",
        "AXOutline",
        "AXTable",
        "AXImage",
        "AXMenu",
        "AXMenuItem",
        "AXMenuBar",
        "AXMenuBarItem",
        "AXToolbar",
        "AXScrollBar",
        "AXSlider",
    ]

    /// The role or subrole of password fields. The reader treats any element classified `.secureText` as
    /// hidden (§3.3).
    package static let secureTextRole = "AXSecureTextField"
    package static let singleLineTextRoles: Set<String> = ["AXTextField", "AXSearchField", "AXComboBox"]
    package static let multiLineTextRoles: Set<String> = ["AXTextArea"]

    /// §2.4 classification. `nil` means unknown, which still pastes. Pure, so both the focus capturer
    /// (Platform) and the reader's hidden-content rule (Core) share it.
    package static func classify(role: String?, subrole: String?) -> ElementKind? {
        if role == secureTextRole || subrole == secureTextRole {
            return .secureText
        }
        if subrole == "AXSearchField" {
            return .singleLineText
        }
        guard let role else { return nil }
        if singleLineTextRoles.contains(role) { return .singleLineText }
        if multiLineTextRoles.contains(role) { return .multiLineText }
        if notTextRoles.contains(role) { return .notEditable }
        return nil
    }
}
