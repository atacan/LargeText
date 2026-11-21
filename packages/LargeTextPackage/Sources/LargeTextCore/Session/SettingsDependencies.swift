import Foundation

package struct SettingsDependencies {
    /// Read whenever the state is rebuilt and written by every setter. Writes to a launch-overridden key stay
    /// in memory (`PreferencesOverlay`); `context` says which.
    package var preferences: any PreferencesStore
    /// Re-read every `permissionRefreshInterval` while the window is visible, and when it becomes key.
    package var permissions: any PermissionsProviding
    /// The two global shortcuts; Kit's `HotkeyBindings`.
    package var shortcuts: any ShortcutBinding
    package var presenter: any SettingsPresenting
    /// Paces the permission refresh; tests park these sleeps.
    package var sleeper: any Sleeper
    /// `nil` hides launch at login (`SettingsState.loginItem == nil`).
    package var loginItem: (any LoginItemControlling)?
    package var context: SettingsContext
    package var permissionRefreshInterval: Duration
    /// Quits and starts the app again ("Relaunch to finish setup").
    package var relaunch: @MainActor () -> Void

    package init(
        preferences: any PreferencesStore,
        permissions: any PermissionsProviding,
        shortcuts: any ShortcutBinding,
        presenter: any SettingsPresenting,
        sleeper: any Sleeper,
        loginItem: (any LoginItemControlling)? = nil,
        context: SettingsContext = .standard,
        permissionRefreshInterval: Duration = .seconds(1),
        relaunch: @escaping @MainActor () -> Void
    ) {
        self.preferences = preferences
        self.permissions = permissions
        self.shortcuts = shortcuts
        self.presenter = presenter
        self.sleeper = sleeper
        self.loginItem = loginItem
        self.context = context
        self.permissionRefreshInterval = permissionRefreshInterval
        self.relaunch = relaunch
    }
}
