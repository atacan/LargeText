import AppKit
import os

/// "Relaunch to finish setup", from the status menu and from Settings.
@MainActor
package enum AppRelauncher {
    /// Waits for this process to exit, then reopens the app bundle, so the new instance can register the
    /// hotkey and pick up the event-posting permission (spike 0i).
    /// - Parameter onFailure: called instead of quitting when the helper can't be started.
    package static func relaunch(onFailure: @MainActor () -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            // Gives up after ~10 s in case termination is ever cancelled.
            """
            i=0; while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do \
            [ $i -ge 100 ] && exit 1; i=$((i+1)); sleep 0.1; done; /usr/bin/open "$0"
            """,
            Bundle.main.bundlePath,
        ]
        do {
            try process.run()
        } catch {
            Logger.ui.error("Relaunch failed: \(error.localizedDescription, privacy: .public)")
            onFailure()
            return
        }
        NSApp.terminate(nil)
    }
}
