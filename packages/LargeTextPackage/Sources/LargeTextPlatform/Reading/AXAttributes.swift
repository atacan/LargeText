import ApplicationServices
import CoreGraphics
import Foundation

/// AX errors that abort a whole read (§4.3). Every other error (unsupported, no value, invalid element, …)
/// only leaves the field `nil`.
package enum AXReadError: Error, Equatable, Sendable {
    /// `kAXErrorCannotComplete`: the app is busy or hung, or the 0.1 s messaging timeout expired.
    case cannotComplete
    /// `kAXErrorAPIDisabled`: Accessibility trust is missing or was revoked mid-session.
    case apiDisabled

    /// `true` on success, `false` when the field should stay `nil`; throws for the errors above.
    package static func check(_ error: AXError) throws(AXReadError) -> Bool {
        switch error {
        case .success: return true
        case .cannotComplete: throw .cannotComplete
        case .apiDisabled: throw .apiDisabled
        default: return false
        }
    }
}

/// Counts the cross-process AX calls of one read, for the per-read budget log (§4.4). Not `Sendable`: one
/// counter belongs to one read on the reader's queue.
package final class AXCallCounter {
    package private(set) var count = 0

    package init() {}

    func record() {
        count += 1
    }
}

/// Typed wrappers around the AX attribute calls of one element (§5.2).
///
/// Reads return `nil` for unsupported attributes, missing values and values of the wrong type, and throw
/// `AXReadError` for the errors that abort a read. Not `Sendable` (it holds an `AXUIElement`): it lives
/// only inside the reader's actor or another single-threaded caller.
package struct AXAttributes {
    package let element: AXUIElement
    package let calls: AXCallCounter

    package init(_ element: AXUIElement, calls: AXCallCounter = AXCallCounter()) {
        self.element = element
        self.calls = calls
    }

    /// The same call counter on another element, e.g. a child or parent.
    package func on(_ other: AXUIElement) -> AXAttributes {
        AXAttributes(other, calls: calls)
    }

    /// The owning process; local, not a cross-process call.
    package var pid: pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(element, &pid) == .success ? pid : nil
    }

    // MARK: - Plain attributes

    package func value(_ attribute: String) throws(AXReadError) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        calls.record()
        guard try AXReadError.check(error) else { return nil }
        return value
    }

    package func string(_ attribute: String) throws(AXReadError) -> String? {
        try value(attribute) as? String
    }

    package func int(_ attribute: String) throws(AXReadError) -> Int? {
        try (value(attribute) as? NSNumber)?.intValue
    }

    package func range(_ attribute: String) throws(AXReadError) -> Range<Int>? {
        try AXValueBox.range(from: value(attribute))
    }

    package func point(_ attribute: String) throws(AXReadError) -> CGPoint? {
        try AXValueBox.point(from: value(attribute))
    }

    package func size(_ attribute: String) throws(AXReadError) -> CGSize? {
        try AXValueBox.size(from: value(attribute))
    }

    package func rect(_ attribute: String) throws(AXReadError) -> CGRect? {
        try AXValueBox.rect(from: value(attribute))
    }

    package func element(_ attribute: String) throws(AXReadError) -> AXUIElement? {
        try AXValueBox.element(from: value(attribute))
    }

    /// At most `maxCount` elements of an array attribute starting at `index`, e.g. the first 20 children,
    /// without copying the whole array.
    package func elements(_ attribute: String, from index: Int = 0, maxCount: Int) throws(AXReadError) -> [AXUIElement] {
        var values: CFArray?
        let error = AXUIElementCopyAttributeValues(element, attribute as CFString, index, maxCount, &values)
        calls.record()
        guard try AXReadError.check(error), let array = values as? [AnyObject] else { return [] }
        return array.compactMap(AXValueBox.element(from:))
    }

    /// The number of values of an array attribute, e.g. children for `AXAppPreparer.isEmptyHit`.
    package func count(_ attribute: String) throws(AXReadError) -> Int? {
        var count: CFIndex = 0
        let error = AXUIElementGetAttributeValueCount(element, attribute as CFString, &count)
        calls.record()
        guard try AXReadError.check(error) else { return nil }
        return count
    }

    /// One `AXUIElementCopyMultipleAttributeValues` call. A failed attribute is `nil` in the result.
    package func batch(_ attributes: [String]) throws(AXReadError) -> AXBatchResult {
        var values: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(
            element,
            attributes as CFArray,
            AXCopyMultipleAttributeOptions(rawValue: 0),
            &values
        )
        calls.record()
        guard try AXReadError.check(error) else { return AXBatchResult(attributes: attributes, values: []) }
        return AXBatchResult(attributes: attributes, array: values)
    }

    /// Attribute names, for the probe only; the reader never needs them.
    package func attributeNames() throws(AXReadError) -> [String] {
        var names: CFArray?
        let error = AXUIElementCopyAttributeNames(element, &names)
        calls.record()
        guard try AXReadError.check(error) else { return [] }
        return (names as? [String]) ?? []
    }

    // MARK: - Parameterized attributes

    package func parameterizedAttributeNames() throws(AXReadError) -> Set<String> {
        var names: CFArray?
        let error = AXUIElementCopyParameterizedAttributeNames(element, &names)
        calls.record()
        guard try AXReadError.check(error) else { return [] }
        return Set((names as? [String]) ?? [])
    }

    package func parameterized(_ attribute: String, _ parameter: CFTypeRef) throws(AXReadError) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &value)
        calls.record()
        guard try AXReadError.check(error) else { return nil }
        return value
    }

    package func string(_ attribute: String, for range: Range<Int>) throws(AXReadError) -> String? {
        try parameterized(attribute, AXValueBox.make(range)) as? String
    }

    package func rect(_ attribute: String, for range: Range<Int>) throws(AXReadError) -> CGRect? {
        try AXValueBox.rect(from: parameterized(attribute, AXValueBox.make(range)))
    }

    package func range(_ attribute: String, for point: CGPoint) throws(AXReadError) -> Range<Int>? {
        try AXValueBox.range(from: parameterized(attribute, AXValueBox.make(point)))
    }
}

/// Packing and unpacking of `AXValue` and `AXUIElement` values.
enum AXValueBox {
    static func make(_ range: Range<Int>) -> AXValue {
        var cfRange = CFRange(location: range.lowerBound, length: range.count)
        return AXValueCreate(.cfRange, &cfRange)!  // only fails for an invalid type
    }

    static func make(_ point: CGPoint) -> AXValue {
        var point = point
        return AXValueCreate(.cgPoint, &point)!
    }

    static func range(from value: CFTypeRef?) -> Range<Int>? {
        var cfRange = CFRange()
        guard let axValue = axValue(value, ofType: .cfRange), AXValueGetValue(axValue, .cfRange, &cfRange),
              cfRange.location >= 0, cfRange.length >= 0 else { return nil }
        return cfRange.location..<(cfRange.location + cfRange.length)
    }

    static func point(from value: CFTypeRef?) -> CGPoint? {
        var point = CGPoint.zero
        guard let axValue = axValue(value, ofType: .cgPoint), AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(from value: CFTypeRef?) -> CGSize? {
        var size = CGSize.zero
        guard let axValue = axValue(value, ofType: .cgSize), AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    static func rect(from value: CFTypeRef?) -> CGRect? {
        var rect = CGRect.zero
        guard let axValue = axValue(value, ofType: .cgRect), AXValueGetValue(axValue, .cgRect, &rect) else { return nil }
        return rect
    }

    static func element(from value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)  // type ID checked above
    }

    private static func axValue(_ value: CFTypeRef?, ofType type: AXValueType) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue  // type ID checked above
        return AXValueGetType(axValue) == type ? axValue : nil
    }
}
