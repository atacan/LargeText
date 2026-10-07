import Foundation
import Testing
@testable import LargeTextPlatform

@Suite struct AXAppFamilyTests {
    @Test(arguments: [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "company.thebrowser.Browser",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
    ])
    func chromiumBrowsersByBundleID(_ bundleIdentifier: String) {
        #expect(AXAppFamily.classify(bundleIdentifier: bundleIdentifier, bundleURL: nil) { _ in false } == .chromiumBrowser)
    }

    @Test func bundleIDWinsWithoutTouchingTheFileSystem() {
        let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        let family = AXAppFamily.classify(bundleIdentifier: "com.google.Chrome", bundleURL: chrome) { _ in
            Issue.record("The Electron check must not run for a known browser")
            return true
        }
        #expect(family == .chromiumBrowser)
    }

    @Test func safariAndFirefoxAreOtherBrowsers() {
        #expect(AXAppFamily.classify(bundleIdentifier: "com.apple.Safari", bundleURL: nil) == .otherBrowser)
        #expect(AXAppFamily.classify(bundleIdentifier: "org.mozilla.firefox", bundleURL: nil) == .otherBrowser)
    }

    @Test func electronIsDetectedByItsFramework() {
        let slack = URL(fileURLWithPath: "/Applications/Slack.app")
        let family = AXAppFamily.classify(bundleIdentifier: "com.tinyspeck.slackmacgap", bundleURL: slack) {
            $0 == "/Applications/Slack.app/Contents/Frameworks/Electron Framework.framework"
        }
        #expect(family == .electron)
    }

    @Test func unknownAppsAreNative() {
        let notes = URL(fileURLWithPath: "/System/Applications/Notes.app")
        #expect(AXAppFamily.classify(bundleIdentifier: "com.apple.Notes", bundleURL: notes) { _ in false } == .native)
        #expect(AXAppFamily.classify(bundleIdentifier: nil, bundleURL: nil) == .native)
        // Case matters: bundle IDs are compared exactly.
        #expect(AXAppFamily.classify(bundleIdentifier: "com.google.chrome", bundleURL: nil) { _ in false } == .native)
    }

    @Test func onlyNativeAppsDontHostWebContent() {
        #expect(AXAppFamily.chromiumBrowser.hostsWebContent)
        #expect(AXAppFamily.otherBrowser.hostsWebContent)
        #expect(AXAppFamily.electron.hostsWebContent)
        #expect(!AXAppFamily.native.hostsWebContent)
    }
}
