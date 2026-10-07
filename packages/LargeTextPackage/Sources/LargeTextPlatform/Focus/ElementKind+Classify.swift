import LargeTextCore

extension ElementKind {
    /// Roles that are definitely not text input. Only these become `.notEditable` (copy-only); anything
    /// ambiguous (e.g. `AXGroup`, `AXWebArea` used by contenteditable editors) stays unknown and is pasted.
    static let notTextRoles: Set<String> = [
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

    static let singleLineTextRoles: Set<String> = ["AXTextField", "AXSearchField", "AXComboBox"]
    static let multiLineTextRoles: Set<String> = ["AXTextArea"]

    /// §2.4 classification. `nil` means unknown, which still pastes.
    package static func classify(role: String?, subrole: String?) -> ElementKind? {
        if role == "AXSecureTextField" || subrole == "AXSecureTextField" {
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
