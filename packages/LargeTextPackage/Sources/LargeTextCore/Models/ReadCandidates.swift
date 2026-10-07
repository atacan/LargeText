import CoreGraphics
import Foundation

/// The next expensive extraction step, named by Core's `ReadPlan` and run by Platform (§4.3).
package enum ReadStep: Hashable, Sendable {
    /// Fetch `value`; only for short elements.
    case value
    /// Selection under the pointer (native or web).
    case selection
    /// `TextWindow` around the pointer index (native).
    case textWindow
    /// Sentence/line/paragraph via text markers (web).
    case textMarkers
    /// Bounded child/ancestor walk.
    case walk
    case done
}

/// A piece of text with its on-screen bounds.
package struct TextSpan: Equatable, Sendable {
    package var text: String
    /// AppKit global coordinates; `nil` when the app did not report bounds.
    package var frame: CGRect?

    package init(text: String, frame: CGRect? = nil) {
        self.text = text
        self.frame = frame
    }
}

/// Text around the pointer, fetched instead of the element's full text. All offsets are UTF-16.
package struct TextWindow: Equatable, Sendable {
    /// About `indexAtPointer` ± 2 000 units, clamped to the element's character count.
    package var text: String
    /// Offset of `text` in the element.
    package var start: Int
    /// Offset of the pointer in the element.
    package var indexAtPointer: Int

    package init(text: String, start: Int, indexAtPointer: Int) {
        self.text = text
        self.start = start
        self.indexAtPointer = indexAtPointer
    }
}

/// Everything gathered so far about the element under the pointer (§4.3). Stage 0 fills the cheap fields;
/// each `ReadStep` adds its own. A step that is unsupported or fails leaves its fields `nil`.
///
/// All rects are AppKit global coordinates: Platform converts exactly once, at its boundary.
package struct ReadCandidates: Equatable, Sendable {
    package var pid: Int32
    package var bundleIdentifier: String?
    package var role: String?
    package var subrole: String?
    package var title: String?
    package var description: String?
    package var help: String?
    package var placeholder: String?
    /// Only filled by `ReadStep.value`, never in stage 0.
    package var value: String?
    package var characterCount: Int?
    package var elementFrame: CGRect?
    /// Set only if the pointer is inside the selection.
    package var selection: TextSpan?
    package var window: TextWindow?
    /// Web path: unit → text + bounds.
    package var markerUnits: [ReadGranularity: TextSpan]
    package var childTexts: [String]
    package var ancestorLabel: String?
    /// A secure element was seen in the walks.
    package var hiddenEncountered: Bool
    /// `AXUIElementCopyParameterizedAttributeNames` of the hit element. When stage 0 found the `AXWebArea` by
    /// walking up, it also holds that web area's text-marker attributes, since the web steps run there.
    package var supportedParameterized: Set<String>
    /// `supportedParameterized` contains `AXTextMarkerForPosition`, or (browser and Electron pids only) an
    /// `AXWebArea` ancestor was found.
    package var webArea: Bool
    /// `ReadPlan` never returns a step in here, so the extraction loop always ends.
    package var attemptedSteps: Set<ReadStep>

    package init(
        pid: Int32,
        bundleIdentifier: String? = nil,
        role: String? = nil,
        subrole: String? = nil,
        title: String? = nil,
        description: String? = nil,
        help: String? = nil,
        placeholder: String? = nil,
        value: String? = nil,
        characterCount: Int? = nil,
        elementFrame: CGRect? = nil,
        selection: TextSpan? = nil,
        window: TextWindow? = nil,
        markerUnits: [ReadGranularity: TextSpan] = [:],
        childTexts: [String] = [],
        ancestorLabel: String? = nil,
        hiddenEncountered: Bool = false,
        supportedParameterized: Set<String> = [],
        webArea: Bool = false,
        attemptedSteps: Set<ReadStep> = []
    ) {
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.role = role
        self.subrole = subrole
        self.title = title
        self.description = description
        self.help = help
        self.placeholder = placeholder
        self.value = value
        self.characterCount = characterCount
        self.elementFrame = elementFrame
        self.selection = selection
        self.window = window
        self.markerUnits = markerUnits
        self.childTexts = childTexts
        self.ancestorLabel = ancestorLabel
        self.hiddenEncountered = hiddenEncountered
        self.supportedParameterized = supportedParameterized
        self.webArea = webArea
        self.attemptedSteps = attemptedSteps
    }
}
