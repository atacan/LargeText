import ApplicationServices
import CoreGraphics
import Foundation
import Testing
@testable import LargeTextPlatform

@Suite struct AXBatchResultTests {
    let attributes = ["AXRole", "AXSubrole", "AXSelectedText", "AXPosition", "AXSize"]

    func errorValue(_ error: AXError = .noValue) -> AnyObject {
        var error = error
        return AXValueCreate(.axError, &error)!
    }

    func pointValue(_ point: CGPoint) -> AnyObject {
        var point = point
        return AXValueCreate(.cgPoint, &point)!
    }

    func sizeValue(_ size: CGSize) -> AnyObject {
        var size = size
        return AXValueCreate(.cgSize, &size)!
    }

    @Test func unwrapsTypedValues() {
        let result = AXBatchResult(
            attributes: attributes,
            values: [
                "AXTextField" as NSString,
                "AXSearchField" as NSString,
                "hello" as NSString,
                pointValue(CGPoint(x: 10, y: 20)),
                sizeValue(CGSize(width: 300, height: 24)),
            ]
        )
        #expect(result.string(for: "AXRole") == "AXTextField")
        #expect(result.string(for: "AXSubrole") == "AXSearchField")
        #expect(result.string(for: "AXSelectedText") == "hello")
        #expect(result.point(for: "AXPosition") == CGPoint(x: 10, y: 20))
        #expect(result.size(for: "AXSize") == CGSize(width: 300, height: 24))
    }

    @Test func axErrorValuesBecomeNil() {
        let result = AXBatchResult(
            attributes: attributes,
            values: [
                "AXGroup" as NSString,
                errorValue(.attributeUnsupported),
                errorValue(.noValue),
                errorValue(.cannotComplete),
                kCFNull,
            ]
        )
        #expect(result.string(for: "AXRole") == "AXGroup")
        #expect(result.value(for: "AXSubrole") == nil)
        #expect(result.string(for: "AXSelectedText") == nil)
        #expect(result.point(for: "AXPosition") == nil)
        #expect(result.size(for: "AXSize") == nil)
    }

    @Test func wrongValueTypesBecomeNil() {
        let result = AXBatchResult(
            attributes: attributes,
            values: [
                pointValue(.zero),            // role is not a string
                "x" as NSString,
                NSNumber(value: 3),           // selected text is not a string
                sizeValue(CGSize(width: 1, height: 1)),  // position holds a size
                pointValue(CGPoint(x: 1, y: 1)),         // size holds a point
            ]
        )
        #expect(result.string(for: "AXRole") == nil)
        #expect(result.string(for: "AXSelectedText") == nil)
        #expect(result.point(for: "AXPosition") == nil)
        #expect(result.size(for: "AXSize") == nil)
    }

    @Test func shortOrMissingArrayYieldsNil() {
        let short = AXBatchResult(attributes: attributes, values: ["AXTextArea" as NSString])
        #expect(short.string(for: "AXRole") == "AXTextArea")
        #expect(short.string(for: "AXSelectedText") == nil)

        let missing = AXBatchResult(attributes: attributes, array: nil)
        #expect(missing.string(for: "AXRole") == nil)
        #expect(missing.value(for: "AXUnrequested") == nil)
    }

    @Test func initFromCFArray() {
        let values: [AnyObject] = ["AXTextArea" as NSString, errorValue()]
        let result = AXBatchResult(attributes: attributes, array: values as CFArray)
        #expect(result.string(for: "AXRole") == "AXTextArea")
        #expect(result.value(for: "AXSubrole") == nil)
    }
}
