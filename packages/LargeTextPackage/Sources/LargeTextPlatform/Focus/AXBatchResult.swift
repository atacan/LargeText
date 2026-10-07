import ApplicationServices
import CoreFoundation
import CoreGraphics

/// Unwraps the array returned by `AXUIElementCopyMultipleAttributeValues`.
///
/// A failed attribute comes back as an `AXValue` of type `kAXValueAXErrorType` (and a missing one may be
/// `kCFNull`); both are exposed as `nil`. Values are looked up by attribute name, so the reader never
/// depends on array positions. Not `Sendable` (it holds CF objects); it is a short-lived local.
package struct AXBatchResult {
    private let valuesByAttribute: [String: AnyObject]

    /// `values[i]` belongs to `attributes[i]`. Extra or missing entries are ignored.
    package init(attributes: [String], values: [AnyObject]) {
        var map: [String: AnyObject] = [:]
        for (attribute, value) in zip(attributes, values) where !Self.isError(value) {
            map[attribute] = value
        }
        valuesByAttribute = map
    }

    /// Convenience for the raw `CFArray?` out-parameter.
    package init(attributes: [String], array: CFArray?) {
        self.init(attributes: attributes, values: (array as? [AnyObject]) ?? [])
    }

    /// The raw value, or `nil` when the attribute failed, was null, or was not requested.
    package func value(for attribute: String) -> AnyObject? {
        valuesByAttribute[attribute]
    }

    package func string(for attribute: String) -> String? {
        value(for: attribute) as? String
    }

    package func point(for attribute: String) -> CGPoint? {
        var point = CGPoint.zero
        guard let axValue = axValue(for: attribute, ofType: .cgPoint),
              AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    package func size(for attribute: String) -> CGSize? {
        var size = CGSize.zero
        guard let axValue = axValue(for: attribute, ofType: .cgSize),
              AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    private func axValue(for attribute: String, ofType type: AXValueType) -> AXValue? {
        guard let value = value(for: attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue  // type ID checked above
        return AXValueGetType(axValue) == type ? axValue : nil
    }

    private static func isError(_ value: AnyObject) -> Bool {
        let typeID = CFGetTypeID(value)
        if typeID == CFNullGetTypeID() { return true }
        if typeID == AXValueGetTypeID() {
            return AXValueGetType(value as! AXValue) == .axError
        }
        return false
    }
}
