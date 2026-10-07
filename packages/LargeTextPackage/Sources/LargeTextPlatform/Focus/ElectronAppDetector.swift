import Foundation

/// Recognizes Electron apps by their bundled framework. Electron keeps its accessibility tree off until a
/// client sets `AXManualAccessibility` (spike 0j).
package enum ElectronAppDetector {
    static let frameworkPath = "Contents/Frameworks/Electron Framework.framework"

    package static func isElectron(
        bundleURL: URL?,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Bool {
        guard let bundleURL else { return false }
        return fileExists(bundleURL.appendingPathComponent(frameworkPath).path)
    }
}
