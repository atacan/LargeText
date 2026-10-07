import AppKit
import os

/// The public entry point. A host app's `main.swift` is just:
///
/// ```swift
/// import LargeTextKit
/// LargeTextApplication.run()
/// ```
@MainActor
public enum LargeTextApplication {
    /// `NSApplication.delegate` is weak, so the controller is kept alive here.
    private static var controller: AppController?

    /// Builds the environment (live → scenario and launch overrides), creates the `AppController`, sets it as
    /// the delegate, runs `NSApplication`, then exits.
    public static func run(launch: LaunchConfiguration = .current) -> Never {
        let app = NSApplication.shared
        var environment = AppEnvironment.live()
        launch.apply(to: &environment)
        let controller = AppController(environment: environment, launch: launch)
        self.controller = controller
        app.delegate = controller
        app.run()
        exit(0)
    }
}
