import Foundation

/// What kind of app owns an element, as far as reading its accessibility tree is concerned (§4.3, §4.11).
package enum AXAppFamily: Hashable, Sendable {
    /// Chrome and its relatives: the tree may need `AXManualAccessibility` (spike R3).
    case chromiumBrowser
    /// Safari and Firefox: web content, but no switch to flip.
    case otherBrowser
    /// Keeps its tree off until a client sets `AXManualAccessibility` (spike 0j).
    case electron
    case native

    /// Chromium-based browsers by bundle ID; their bundles don't contain the Electron framework.
    static let chromiumBundleIdentifiers: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "company.thebrowser.Browser",  // Arc
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
    ]

    static let otherBrowserBundleIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
    ]

    /// Bundle IDs are checked first, so the file check only runs for apps that aren't known browsers.
    package static func classify(
        bundleIdentifier: String?,
        bundleURL: URL?,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> AXAppFamily {
        if let bundleIdentifier {
            if chromiumBundleIdentifiers.contains(bundleIdentifier) { return .chromiumBrowser }
            if otherBrowserBundleIdentifiers.contains(bundleIdentifier) { return .otherBrowser }
        }
        return ElectronAppDetector.isElectron(bundleURL: bundleURL, fileExists: fileExists) ? .electron : .native
    }

    /// Browsers and Electron apps host web content, so stage 0 may walk up to an `AXWebArea` (§4.3).
    package var hostsWebContent: Bool {
        self != .native
    }
}
