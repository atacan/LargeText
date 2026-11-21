import Testing
import LargeTextCore

struct PermissionSetupTests {
    @Test func allGrantedNeedsNothing() {
        #expect(Permissions.allGranted.setup == .granted)
    }

    /// Spike 0i: event posting may only start working after a relaunch.
    @Test func postingMissingNeedsARelaunch() {
        #expect(Permissions(accessibility: .granted, eventPosting: .denied).setup == .needsRelaunch)
    }

    @Test func accessibilityMissingNeedsAGrantWhateverPostingSays() {
        #expect(Permissions.allDenied.setup == .needsGrant)
        #expect(Permissions(accessibility: .denied, eventPosting: .granted).setup == .needsGrant)
    }
}
