import Foundation

/// Editor font size rules: default 64 pt, range 24…200 pt, step 8 pt.
package enum FontSizePolicy {
    package static let `default` = FontSize(points: 64)
    package static let range: ClosedRange<Double> = 24...200
    package static let step: Double = 8

    package static func apply(_ zoom: ZoomStep, to size: FontSize) -> FontSize {
        switch zoom {
        case .bigger: clamp(FontSize(points: size.points + step))
        case .smaller: clamp(FontSize(points: size.points - step))
        case .reset: `default`
        }
    }

    /// Brings any size (e.g. a hand-edited preference) into `range`. Non-finite values become `default`.
    package static func clamp(_ size: FontSize) -> FontSize {
        guard size.points.isFinite else { return `default` }
        return FontSize(points: min(max(size.points, range.lowerBound), range.upperBound))
    }
}
