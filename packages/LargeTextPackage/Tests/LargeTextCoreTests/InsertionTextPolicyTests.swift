import Testing
import LargeTextCore

@MainActor
struct InsertionTextPolicyTests {
    @Test func singleLineElementsFlatten() {
        #expect(InsertionTextPolicy.flattensNewlines(for: Fixtures.target(kind: .singleLineText)))
    }

    @Test(arguments: [ElementKind.multiLineText, .notEditable, .secureText, nil])
    func otherKindsInRegularAppsDoNotFlatten(kind: ElementKind?) {
        #expect(!InsertionTextPolicy.flattensNewlines(for: Fixtures.target(kind: kind)))
    }

    @Test(arguments: [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "org.alacritty", "net.kovidgoyal.kitty", "com.github.wez.wezterm", "co.zeit.hyper", "org.tabby",
    ])
    func terminalsFlattenRegardlessOfElementKind(bundleIdentifier: String) {
        let app = TargetApplication(processIdentifier: 1, bundleIdentifier: bundleIdentifier, localizedName: "Term")
        #expect(InsertionTextPolicy.flattensNewlines(for: Fixtures.target(app, kind: nil)))
        #expect(InsertionTextPolicy.flattensNewlines(for: Fixtures.target(app, kind: .multiLineText)))
    }

    @Test func missingApplicationOrBundleIdDoesNotFlattenMultiLine() {
        let anonymous = TargetApplication(processIdentifier: 1, bundleIdentifier: nil, localizedName: "X")
        #expect(!InsertionTextPolicy.flattensNewlines(for: Fixtures.target(nil, kind: .multiLineText)))
        #expect(!InsertionTextPolicy.flattensNewlines(for: Fixtures.target(anonymous, kind: .multiLineText)))
    }

    @Test func prepareReplacesEachNewlineSequenceWithOneSpace() {
        let text = "one\r\ntwo\nthree\rfour\u{2028}five"
        #expect(InsertionTextPolicy.prepare(text, for: Fixtures.target(kind: .singleLineText)) == "one two three four five")
    }

    @Test func prepareKeepsBlankLinesAsSeparateSpaces() {
        #expect(InsertionTextPolicy.prepare("a\n\nb", for: Fixtures.target(Fixtures.terminal, kind: nil)) == "a  b")
    }

    @Test func prepareLeavesTextUnchangedWhenNotFlattening() {
        let text = "one\r\ntwo\nthree"
        #expect(InsertionTextPolicy.prepare(text, for: Fixtures.target(kind: .multiLineText)) == text)
    }
}
