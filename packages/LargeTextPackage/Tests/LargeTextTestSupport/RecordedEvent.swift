import Foundation
import LargeTextCore

/// One observable side effect, appended to a shared `EventLog` by the spies.
package enum RecordedEvent: Equatable, Sendable {
    // Overlay
    case present(initialText: String)
    case update(OverlayChrome)
    case dismiss
    // Pasteboard
    case snapshot
    case write(String, transient: Bool)
    case restore
    // Keystrokes
    case key(Keystroke)
    // Notices
    case notice(Notice)
    // Inserter
    case insert(String, CommitMode)
    // Sleeper
    case sleep(Duration)
}
