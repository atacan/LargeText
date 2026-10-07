import Foundation
import Testing
@testable import LargeTextPlatform

struct ElectronAppDetectorTests {
    @Test func detectsBundledElectronFramework() {
        let slack = URL(fileURLWithPath: "/Applications/Slack.app")
        let isElectron = ElectronAppDetector.isElectron(bundleURL: slack) {
            $0 == "/Applications/Slack.app/Contents/Frameworks/Electron Framework.framework"
        }
        #expect(isElectron)
    }

    @Test func nativeAppsAreNotElectron() {
        let safari = URL(fileURLWithPath: "/Applications/Safari.app")
        #expect(!ElectronAppDetector.isElectron(bundleURL: safari) { _ in false })
    }

    @Test func missingBundleURLIsNotElectron() {
        #expect(!ElectronAppDetector.isElectron(bundleURL: nil) { _ in true })
    }
}
