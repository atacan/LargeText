import Foundation
import LargeTextCore
import ServiceManagement
import Testing
@testable import LargeTextPlatform

/// The pure parts of `SMAppServiceLoginItem` (Settings plan §3.7). Nothing here touches `SMAppService.mainApp`.
@Suite struct LoginItemStatusMappingTests {
    @Test func everySystemStatusMaps() {
        #expect(LoginItemStatus(SMAppService.Status.notRegistered) == .notRegistered)
        #expect(LoginItemStatus(SMAppService.Status.enabled) == .enabled)
        #expect(LoginItemStatus(SMAppService.Status.requiresApproval) == .requiresApproval)
        #expect(LoginItemStatus(SMAppService.Status.notFound) == .notFound)
    }

    @Test func theToggleIsOnForARegisteredItemApprovedOrNot() {
        #expect(LoginItemStatus(SMAppService.Status.enabled).isOn)
        #expect(LoginItemStatus(SMAppService.Status.requiresApproval).isOn)
        #expect(!LoginItemStatus(SMAppService.Status.notRegistered).isOn)
        #expect(!LoginItemStatus(SMAppService.Status.notFound).isOn)
    }

    @Test func theSpelledOutCodesMatchTheFramework() {
        #expect(LoginItemError.Code.authorizationFailure == Int(kSMErrorAuthorizationFailure))
        #expect(LoginItemError.Code.jobNotFound == Int(kSMErrorJobNotFound))
        #expect(LoginItemError.Code.launchDeniedByUser == Int(kSMErrorLaunchDeniedByUser))
        #expect(LoginItemError.Code.alreadyRegistered == Int(kSMErrorAlreadyRegistered))
        #expect(LoginItemError.Code.operationNotPermitted == Int(EPERM))
    }

    @Test func alreadyInTheRequestedStateIsNotAnError() {
        #expect(LoginItemError(registrationError: error(Int(kSMErrorAlreadyRegistered)), enabling: true) == nil)
        #expect(LoginItemError(registrationError: error(Int(kSMErrorJobNotFound)), enabling: false) == nil)
    }

    @Test func theOppositeDirectionStillFails() {
        #expect(LoginItemError(registrationError: error(Int(kSMErrorAlreadyRegistered)), enabling: false) == .failed(code: 12))
        #expect(LoginItemError(registrationError: error(Int(kSMErrorJobNotFound)), enabling: true) == .failed(code: 6))
    }

    @Test(arguments: [true, false])
    func refusalsAreNotPermitted(_ enabling: Bool) {
        for code in [Int(EPERM), Int(kSMErrorAuthorizationFailure), Int(kSMErrorLaunchDeniedByUser)] {
            #expect(LoginItemError(registrationError: error(code), enabling: enabling) == .notPermitted)
        }
    }

    @Test func otherCodesKeepTheCodeForTheLog() {
        #expect(LoginItemError(registrationError: error(Int(kSMErrorInvalidSignature)), enabling: true) == .failed(code: 3))
        #expect(LoginItemError(registrationError: error(Int(kSMErrorInternalFailure)), enabling: false) == .failed(code: 2))
    }

    private func error(_ code: Int) -> NSError {
        NSError(domain: "SMAppServiceErrorDomain", code: code)
    }
}
