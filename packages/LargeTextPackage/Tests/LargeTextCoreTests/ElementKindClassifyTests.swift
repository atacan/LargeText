import Testing
import LargeTextCore

@Suite struct ElementKindClassifyTests {
    @Test(arguments: [
        ("AXGroup", nil), ("AXWebArea", nil), ("AXStaticText", nil), ("AXUnknown", nil), ("AXCell", nil),
    ] as [(String, String?)])
    func ambiguousRolesAreUnknown(role: String, subrole: String?) {
        #expect(ElementKind.classify(role: role, subrole: subrole) == nil)
    }

    @Test func nilRoleIsUnknown() {
        #expect(ElementKind.classify(role: nil, subrole: nil) == nil)
    }

    @Test(arguments: ["AXTextField", "AXSearchField", "AXComboBox"])
    func singleLineRoles(role: String) {
        #expect(ElementKind.classify(role: role, subrole: nil) == .singleLineText)
    }

    @Test func searchFieldSubrole() {
        #expect(ElementKind.classify(role: "AXTextField", subrole: "AXSearchField") == .singleLineText)
        #expect(ElementKind.classify(role: nil, subrole: "AXSearchField") == .singleLineText)
    }

    @Test func textAreaIsMultiLine() {
        #expect(ElementKind.classify(role: "AXTextArea", subrole: nil) == .multiLineText)
    }

    @Test func secureRoleOrSubrole() {
        #expect(ElementKind.classify(role: "AXTextField", subrole: "AXSecureTextField") == .secureText)
        #expect(ElementKind.classify(role: "AXSecureTextField", subrole: nil) == .secureText)
        #expect(ElementKind.classify(role: nil, subrole: "AXSecureTextField") == .secureText)
    }

    @Test(arguments: [
        "AXButton", "AXList", "AXOutline", "AXTable", "AXImage", "AXMenu", "AXMenuItem", "AXMenuBarItem",
        "AXToolbar", "AXScrollBar", "AXSlider", "AXCheckBox", "AXRadioButton", "AXPopUpButton",
    ])
    func explicitNotTextRoles(role: String) {
        #expect(ElementKind.classify(role: role, subrole: nil) == .notEditable)
    }
}
