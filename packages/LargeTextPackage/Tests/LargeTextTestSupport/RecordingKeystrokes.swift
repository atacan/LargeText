import Foundation
import LargeTextCore

/// Records sent keystrokes. Each read of `pressedModifiers` consumes the next scripted value;
/// once the script is exhausted, `restingModifiers` is returned.
@MainActor
package final class RecordingKeystrokes: KeystrokeSending {
    package var scriptedModifiers: [Modifiers]
    package var restingModifiers: Modifiers
    package private(set) var modifierReads = 0
    package private(set) var sent: [Keystroke] = []

    private let log: EventLog?

    package init(scriptedModifiers: [Modifiers] = [], restingModifiers: Modifiers = [], log: EventLog? = nil) {
        self.scriptedModifiers = scriptedModifiers
        self.restingModifiers = restingModifiers
        self.log = log
    }

    package var pressedModifiers: Modifiers {
        modifierReads += 1
        return scriptedModifiers.isEmpty ? restingModifiers : scriptedModifiers.removeFirst()
    }

    package func send(_ stroke: Keystroke) {
        sent.append(stroke)
        log?.append(.key(stroke))
    }
}
