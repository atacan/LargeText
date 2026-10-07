import LargeTextCore
import Testing
@testable import LargeTextPlatform

@Suite struct ClipboardRestorePolicyDefaultsTests {
    @Test(arguments: [
        ("none", ClipboardRestorePolicy.none),
        ("None", .none),
        ("restore", .default),
        ("restore:1024", .restore(maxBytes: 1024)),
        (" restore:1 ", .restore(maxBytes: 1)),
    ])
    func parses(string: String, expected: ClipboardRestorePolicy) {
        #expect(ClipboardRestorePolicy(defaultsString: string) == expected)
    }

    @Test(arguments: ["", "off", "restore:", "restore:0", "restore:-1", "restore:abc", "{\"none\":{}}"])
    func rejectsMalformed(string: String) {
        #expect(ClipboardRestorePolicy(defaultsString: string) == nil)
    }

    @Test(arguments: [ClipboardRestorePolicy.none, .default, .restore(maxBytes: 42)])
    func roundTrips(policy: ClipboardRestorePolicy) {
        #expect(ClipboardRestorePolicy(defaultsString: policy.defaultsString) == policy)
    }

    @Test func formats() {
        #expect(ClipboardRestorePolicy.none.defaultsString == "none")
        #expect(ClipboardRestorePolicy.restore(maxBytes: 10).defaultsString == "restore:10")
    }
}
