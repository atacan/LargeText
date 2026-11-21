# LargeText Settings window — Technical Implementation Plan (draft 1)

Status: implemented (M0–M8) on branch `settings-window`, pending the hands-on checks in
`docs/manual-testing.md` › *Settings*. Product decisions are in §1. The rest is the technical plan as
written; what changed during implementation is in §9.

Most of the work is already done by the current design. Every coordinator reads `PreferencesStore` when a
session starts, and `UserDefaultsPreferencesStore` reads `UserDefaults` on every access. So font sizes, hold
threshold, units and clipboard restore take effect on the next session as soon as they are written. Only
these need active work:

- **both shortcuts**, which must be registered again;
- **the status-menu titles**: `AppController.start()` builds `StatusItemController` with fixed combos, and
  the `onReadTextUnderPointer` closure captures `readerHotkey` by value;
- **the Accessibility status**, which changes outside the app.

---

## 1. Product decisions

| # | Question | Decision |
|---|---|---|
| D1 | Can the Reader shortcut be turned off? | **Yes.** The Reader recorder has a "Turn off" (clear) action. The editor shortcut can only be changed or reset. |
| D2 | Does ⌘, inside the editor or the pinned reader card open Settings? | **Yes.** It closes the card, then opens Settings (§3.5). |
| D3 | Does the app appear in ⌘Tab while Settings is open? | **Yes.** The app switches to `.regular` while the window is open and back to `.accessory` when it closes. This needs a main menu (§3.3). |
| D4 | Separate text sizes for the editor and the reader? | **Yes.** New preference `readerFontSize`, seeded from `fontSize` (§3.4). |
| D5 | Open Settings on first launch when Accessibility is missing? | **Yes**, on the first launch only (§3.6). |
| D6 | What does "Grant Access…" do? | **Adds the app to the Accessibility list** (`requestAccessibility()`, which shows the system prompt), then opens the System Settings pane. The status menu item does the same, so the two never differ. |

Still open: §8.

---

## 2. What the window exposes

| Setting | Control | Notes |
|---|---|---|
| Editor shortcut (`hotkey`) | Shortcut recorder + "Reset" | Rules in §2.1. Can't be turned off. |
| Reader shortcut (`readerHotkey`) | Shortcut recorder + "Reset" + "Turn off" | D1. Off = not registered, and the status menu leaves out "Read Text Under Pointer" (`StatusMenuModel` already accepts `readerHotkey: nil`). |
| Editor text size (`fontSize`) | Slider 24–200 pt, step 8 (`FontSizePolicy.range`, `.step`) + "64 pt" label | ⌘± in the editor still changes it. The window re-reads the store when it becomes key. |
| Reader text size (`readerFontSize`, new) | Same slider | D4. ⌘± on the pinned card changes this one. |
| Hold threshold (`readerHoldThreshold`) | Slider 150–800 ms, step 25 | Add `ReaderDefaults.holdThresholdRange`, `holdThresholdStep` and `clampHoldThreshold`. The store still accepts any positive value from `defaults write`. Disabled while the Reader is off. |
| Following unit, pinned unit | Two pop-ups: Sentence, Line, Paragraph | `ReadGranularity.allCases`. Disabled while the Reader is off. |
| Clipboard restore | Toggle "Restore clipboard after pasting" | On = `.default` (10 MB), off = `.none`. Footnote about the macOS 15.4+ pasteboard prompts. A custom `restore:<bytes>` is kept until the toggle is touched. |
| Accessibility | Status + button | Three states, shared with the menu through `PermissionSetup`: granted; "Grant Access…" (D6); "Relaunch to finish setup". |
| Launch at login | Toggle | `SMAppService.mainApp`, last milestone (§3.7). |
| Reset all | Button | Writes all defaults, registers shortcuts once. |

**Left out of v1:**
- the password-manager denylist (`ReadPolicy.passwordManagers`): a privacy control where a mistake leaks
  passwords. A read-only "Hidden apps" list is possible later.
- `ReadPolicy.elementTextLimit` / `maxCharacters`, `InsertionTiming`, `ReaderTiming.maxFollowDuration`, the
  font size range, clipboard `maxBytes`: engineering limits, not user choices.
- backdrop dimming (`Theme.backdropColor`): open product question in `IMPLEMENTATION_PLAN.md` §8.

### 2.1 Shortcut rules

A pure `ShortcutRules.validate(_:for:other:) -> ShortcutProblem?` in Core:

- `.needsModifier`: no modifier, or ⇧ only. F1–F20 are allowed without modifiers.
- `.optionOnlyRefused`: ⌥ or ⌥⇧ only, which macOS 15 refuses (`IMPLEMENTATION_PLAN.md` §2.1).
- `.reservedBySystem`: a fixed list (⌘Space, ⌃Space, ⌘Tab, ⌘\`, ⌘Q, ⌘W, ⌘,, ⌘⇧3/4/5).
- `.sameAsOther(slot)`: delegates to `HotkeyConflicts.validate`, which stays the single source of truth.
  Skipped when the other slot is off.
- `.unavailable`: set by the coordinator when registration fails.

Conflicts with other apps can't be detected reliably (spike 0g is still open), so the recorder says
"If it doesn't respond, another app may be using it."

---

## 3. Key technical decisions

### 3.1 Window technology

**An AppKit `NSWindow` owned by `SettingsWindowController`, with `NSHostingController(rootView: SettingsView)`
as content.** `SettingsView` is a SwiftUI `Form` with `.formStyle(.grouped)`. The shortcut recorder is an
AppKit `NSView` wrapped in `NSViewRepresentable`.

Rejected: the SwiftUI `Settings` scene. It needs a SwiftUI `@main App`, which would replace `main.swift`,
`LargeTextApplication.run()` and `AppController` as delegate, and it can only be opened through the
`openSettings` environment action from inside a SwiftUI view.

Fallback: pure AppKit with `NSGridView`, if recorder focus inside the SwiftUI `Form` causes trouble. The
`SettingsState` / `SettingsIntent` boundary makes that a UI-only swap.

### 3.2 Opening the window

- Status menu: new item "Settings…" with key equivalent ",", before the separator and Quit.
- ⌘, in the editor or pinned reader (D2, §3.5).
- First launch with Accessibility missing (D5, §3.6).
- `--present-settings-on-launch`.
- In the main menu while Settings is open (§3.3).

A global ⌘, is not possible: it would take ⌘, away from every app.

### 3.3 Activation policy and main menu (D3)

The app is an accessory app (`LSUIElement = YES`) with no `NSApp.mainMenu`.

**Showing the window:**
1. Remember `NSWorkspace.shared.frontmostApplication`.
2. Install the main menu if it isn't installed yet (below).
3. `NSApp.setActivationPolicy(.regular)`. The Dock icon and the ⌘Tab entry appear.
4. `NSApp.activate()` (cooperative activation, macOS 14), then `window.makeKeyAndOrderFront(nil)`.

**Closing the window** (`windowWillClose`):
1. `NSApp.setActivationPolicy(.accessory)`.
2. Re-activate the remembered app if it is still running, so focus doesn't drop into an app with no window.
   Don't use `NSApp.hide`: a hidden app may not show the non-activating panels afterwards.

Window settings: `collectionBehavior = [.moveToActiveSpace]`, `isReleasedWhenClosed = false`,
`hidesOnDeactivate = false`, `setFrameAutosaveName("LargeText.Settings")`.

**Main menu** (`MainMenuBuilder`, UI). A Dock icon with an empty app menu looks broken, so the package
installs a minimal menu once, at startup:
- *LargeText*: About LargeText, Settings… (⌘,), Hide (⌘H), Quit LargeText (⌘Q)
- *Edit*: Undo, Redo, Cut, Copy, Paste, Select All (standard selectors)
- *Window*: Minimize (⌘M), Close (⌘W)

The menu also fixes key equivalents in the window (⌘W, and ⌘C / ⌘V if text fields are added later), so no
`performKeyEquivalent` override is needed except ⎋ → close (`cancelOperation:`).

Points to check by hand:
- The editor and pinned reader panels are key windows of an app that isn't active, so the main menu is
  not consulted for their keys. While Settings is open, LargeText *is* active: check that ⌘± and ⌘↩ in the
  editor still reach `EditorKeyBindings` and aren't taken by a menu item.
- The policy switch must not flash the Dock when Settings opens over a full-screen app.
- While Settings is frontmost, an editor commit is copy-only (focus capture skips AX when LargeText is
  frontmost, `AccessibilityFocusCapturer.swift`), and the reader over the window shows nothing
  (`.ownProcess`, `AXHitTester.swift`). Both are expected.

### 3.4 Separate reader text size (D4)

- `PreferencesStore`: add `readerFontSize: FontSize`.
- `UserDefaultsPreferencesStore`: key `LargeText.readerFontSize`. When it is unset, return the current
  `fontSize`, so existing users keep the size they have. It is written on the first reader zoom or Settings
  change.
- `ReadingSessionCoordinator`: read `readerFontSize` when a session starts (today `fontSize`, line ~115) and
  write `readerFontSize` on zoom (today line ~345). Update the comment in `ReaderDependencies.swift`.
- `InMemoryPreferencesStore` and `PreferencesOverlay`: add the field.
- Docs: README, `READER_IMPLEMENTATION_PLAN.md` §1 and §10.3 ("shared through the `fontSize`
  preference"), and the website, which says "the Reader uses the same size".

### 3.5 ⌘, in the editor and the reader (D2)

- `CommandShortcutMatcher`: add `","` → `.openSettings`, by character, with the ANSI comma key code
  (0x2B) as the fallback for non-ASCII layouts, like the other shortcuts.
- `EditorKeyBindings` → `EditorAction.openSettings`; `ReaderKeyBindings` → `ReaderAction.openSettings`.
  Only the pinned card can receive it, because the following card is never key.
- Editor: **closes like ⎋ (cancel), but only when the text is empty.** With text in the editor, the
  text is copied to the clipboard first (`ClipboardWriter`, HUD "Copied — press ⌘V") so it isn't lost.
  Then Settings opens. See §8 Q1.
- Reader: closes, then Settings opens.
- Both go through one path, `AppController.openSettings()`, which already closes the reader and the
  editor first.

### 3.6 First launch (D5) and Grant Access (D6)

- `PreferencesStore`: add `hasCompletedFirstLaunch: Bool` (key `LargeText.hasCompletedFirstLaunch`).
- `AppController.start()`, step 5: if access is missing **and** it's the first launch, open Settings, then
  call `requestAccessibility()`. The system prompt appears over the window, and the window's Accessibility
  row is visible when the prompt closes. Then set `hasCompletedFirstLaunch = true`. On later launches the
  current behaviour stays: `requestAccessibility()` only. `--present-on-launch` keeps deferring the prompt.
- "Grant Access…", in the menu and in the window: `requestAccessibility()` (adds LargeText to the
  Accessibility list and shows the prompt), then `openSystemSettings()`. Today the menu only opens System
  Settings.
- The macOS prompt is only shown while the app isn't trusted. If the user removed LargeText from the
  list, calling it again adds it back. Check by hand with `tccutil reset Accessibility com.actondon.LargeText`.

### 3.7 Launch at login

`SMAppService.mainApp` works for an unsandboxed Developer ID app. The system is the source of truth, not
`UserDefaults`. Handle `.requiresApproval` with a link to `SMAppService.openSystemSettingsLoginItems()`.
Builds from DerivedData register their build path, so test it from an exported build in /Applications.
Scenarios swap in `InMemoryLoginItem`, so tests never touch system state.

### 3.8 How changes take effect

There is no global observation (no KVO, Combine or `UserDefaults.didChangeNotification`).
`SettingsCoordinator` (Core) is the only writer from the UI. It writes to `PreferencesStore` and calls
ports for side effects.

**Shortcuts.** Move registration out of `AppController.startSessions()` into a Kit class `HotkeyBindings`
behind a Core port:

```swift
@MainActor package protocol ShortcutBinding: AnyObject {
    /// Unregisters both, then registers the editor and, when non-nil, the reader (with HotkeyConflicts).
    func apply(editor: KeyCombo, reader: KeyCombo?) -> [ShortcutSlot: HotkeyError]
    /// Unregisters both while a recorder is recording.
    func suspend()
    var unavailable: [KeyCombo] { get }
}
```

- Unregister everything, then register. This avoids ordering bugs when the two combos swap: Carbon
  refuses a duplicate in the same process (`eventHotKeyExistsErr`).
- On a recorded combo: `ShortcutRules` → `apply(new)` → on failure `apply(old)`, don't save, show
  `.unavailable`; on success, save.
- Turning the Reader off: save `readerHotkey = nil`, then `apply(editor, nil)`.
- `HotkeyBindings.onChange` lets `AppController` update the status item's combos and
  `hotkeyUnavailable`. The menu already rebuilds in `menuNeedsUpdate`. `AppController.hotkeyUnavailable`
  becomes computed, so existing tests still compile. `onReadTextUnderPointer` reads
  `preferences.readerHotkey` when called.
- **Recording suspends both global shortcuts.** Otherwise ⌃⌥⌘T in the recorder opens the editor.
  `.beginRecording` → `suspend()`; `.record`, `.cancelRecording`, window closed, window resigns key →
  `apply(current or new)`. A crash while recording loses nothing, since combos are saved only after a
  successful `apply`.

**Optional reader shortcut (D1).** `PreferencesStore.readerHotkey` becomes `KeyCombo?`.
- `UserDefaultsPreferencesStore`: missing key = default (⌃⌥⌘R, as now). The string `"off"` = `nil`.
  Writing `nil` stores `"off"`, not a deleted key, so "off" survives.
- `HotkeyConflicts.validate` is only called when the reader combo is non-nil.
- `ReadingSessionCoordinator` reads the combo when a session starts, for the stuck-key check. Without a
  registration, no session can start, so it never sees `nil`. Unwrap with a logged early return.

**Accessibility.** While the window is visible, the coordinator re-reads `permissions.current` every
second through the `Sleeper` port (tests use `RecordingSleeper`), and on `windowDidBecomeKey`.

**Launch-argument overrides.** Writes to a key overridden on the command line stay in memory
(`PreferencesOverlay.swift`). The window shows the active value with a note: "Set by
`--reader-hold-threshold` for this run; not saved." Kit passes
`SettingsContext(scenarioName:, launchOverrides: Set<PreferenceKey>)` to the coordinator. With a scenario
active (all use `InMemoryPreferencesStore`), a banner says "Scenario '…': changes are kept in memory
only."

---

## 4. Modules, types and files

**Core** (`Sources/LargeTextCore/`)
- `Settings/`: `ShortcutSlot`, `ShortcutRules`, `ShortcutProblem`, `SettingsState`, `SettingsIntent`,
  `SettingsContext`, `PreferenceKey`.
  - `SettingsState`: a `Sendable` value. Per shortcut `{combo: KeyCombo?, isRecording, problem,
    isRegistered}`; `editorFontSize`, `readerFontSize`, `holdThreshold`, both units, `restoresClipboard`,
    `permission: PermissionSetup`, `loginItem: LoginItemStatus?`, `context`.
  - `SettingsIntent`: `beginRecording(slot)`, `cancelRecording`, `record(slot, combo)`,
    `resetShortcut(slot)`, `turnOffReader`, `setEditorFontSize`, `setReaderFontSize`, `setHoldThreshold`,
    `setFollowingUnit`, `setPinnedUnit`, `setRestoresClipboard`, `setLaunchAtLogin`, `grantAccess`,
    `relaunch`, `openLoginItemsSettings`, `resetAll`, `closed`.
- `Session/SettingsCoordinator.swift`, `Session/SettingsDependencies.swift` (preferences, permissions,
  shortcuts, loginItem, presenter, sleeper, context, `relaunch` closure).
- Ports: `SettingsPresenting` (`show(_:intents:)`, `update(_:)`, `isVisible`), `ShortcutBinding`,
  `LoginItemControlling` (`status`, `setEnabled(_:) throws(LoginItemError)`, `openSystemSettings()`).
- `Ports/PreferencesStore.swift`: `readerHotkey: KeyCombo?`, `readerFontSize`, `hasCompletedFirstLaunch`.
- `Models/Permissions.swift`: `PermissionSetup { granted, needsRelaunch, needsGrant }` and
  `Permissions.setup`; `StatusMenuModel.permissionItem` uses it.
- `Models/ReaderDefaults.swift`: hold-threshold range, step, clamp.
- `Session/ReadingSessionCoordinator.swift`: `readerFontSize`; optional combo.
- `Fakes/`: `InMemoryLoginItem`, `LoggingSettingsPresenter`, `RefusingHotkeyRegistrar` (wraps any
  `HotkeyRegistering` and refuses a given set of combos); `InMemoryPreferencesStore` gets the new fields.

**Platform** (`Sources/LargeTextPlatform/`)
- `LoginItem/SMAppServiceLoginItem.swift`, with a pure `LoginItemStatus.init(_ SMAppService.Status)`.
- `Preferences/UserDefaultsPreferencesStore.swift`: `readerFontSize` (falls back to `fontSize`),
  `readerHotkey` `"off"`, `hasCompletedFirstLaunch`. Update the key list in its header comment.

**UI** (`Sources/LargeTextUI/`)
- `Settings/`: `SettingsWindowController` (implements `SettingsPresenting`, activation policy, close
  handling), `SettingsView` (SwiftUI, via a `@MainActor @Observable SettingsViewModel`),
  `ShortcutRecorderView` (AppKit: `keyDown`, `performKeyEquivalent` for ⌘ combos, `flagsChanged` for live
  "⌃⌥…"), `ShortcutRecorderRepresentable`, `ShortcutKeyInterpreter` (pure: `KeyInput` →
  `cancel | candidate(KeyCombo) | ignore`; reuses `KeyInput` and `Modifiers(eventFlags:)`),
  `SettingsStrings`.
- `Shared/MainMenuBuilder.swift` (§3.3).
- `Shared/AppRelauncher.swift`: `relaunch` moved out of `StatusItem/StatusItemController.swift`.
- `StatusItem/`: `.openSettings` item with ","; `onOpenSettings` closure; Grant Access per D6.
- `Editor/CommandShortcutMatcher.swift`, `EditorKeyBindings.swift`, `EditorAction.swift`,
  `Reader/ReaderKeyBindings.swift`: ⌘, (§3.5).
- `Previews/SettingsPreviews.swift`.
- Known limit: `KeyComboFormatter` names keys by ANSI (US) position.

**Kit** (`Sources/LargeTextKit/`)
- `HotkeyBindings.swift`, extracted from `AppController.startSessions()` and `reportUnavailable`.
- `AppEnvironment.swift`: append `loginItem` (default `InMemoryLoginItem()`) and `settingsPresenter`
  (default `LoggingSettingsPresenter()`); `live()` uses the real ones; add `settingsDependencies(...)`.
- `AppController.swift`: own `SettingsCoordinator`; `openSettings()` closes the reader and editor first;
  first-launch flow (§3.6); install the main menu; wire `onChange`; computed `hotkeyUnavailable`;
  `presentSettingsOnLaunch`.
- `LaunchConfiguration.swift`: `--present-settings-on-launch`. `Scenario.swift`: new scenarios (§5) and
  `InMemoryLoginItem` for every scenario.

---

## 5. Testing

**Core**
- `ShortcutRulesTests`: one test per rule, including "other slot off".
- `PermissionSetupTests`, `ReaderDefaultsClampTests`.
- `SettingsCoordinatorTests`:
  - showing renders the store; each setter writes the clamped value;
  - valid record → `apply(new)`, save, `update`; failed `apply` → `apply(old)`, not saved, `.unavailable`;
    `.sameAsOther` → no `apply`;
  - begin recording → `suspend`; cancel, close, resign → `apply(current)`;
  - turn off reader → save `nil`, `apply(editor, nil)`; reset reader turns it back on;
  - `resetAll` → one `apply`;
  - Grant Access → `requestAccessibility` then `openSystemSettings`;
  - override and scenario notes; clipboard toggle mapping; login item `requiresApproval` and errors;
  - the 1 s permission refresh stops when the window closes.
- `ReadingSessionCoordinatorTests`: reads and writes `readerFontSize`, leaves `fontSize` alone.

**TestSupport**: `SpySettingsPresenter`, `SpyShortcutBinding`, `SpyLoginItem`. `SpyHotkeys` gets
`refusing: Set<KeyCombo>` and refuses a combo that is still registered, as Carbon does, so ordering bugs
show up.

**Platform**: `LoginItemStatusMappingTests`; `UserDefaultsPreferencesStoreTests` for `readerFontSize`
fallback, `"off"`, and `hasCompletedFirstLaunch`.

**Kit**
- `HotkeyBindingsTests`: unregister-all then register; swapped combos; conflict; reader off; `unavailable`
  list; suspend.
- `AppControllerTests`: after a rebind the new combo opens the editor and the old one does nothing; menu
  data refreshed; `openSettings` closes the reader and the editor; first launch with access missing opens
  Settings once, and the second launch doesn't.
- `LaunchConfigurationTests`, `ScenarioTests`; `AppEnvironmentTests.liveEnvironmentIsConstructibleWithoutSideEffects`
  (`SMAppService.mainApp` must not be touched in `init`).

**UI**: `ShortcutKeyInterpreterTests` (⌘ combos, German layout), `SettingsStringsTests`,
`StatusMenuModelTests` ("Settings…", reader off), `EditorKeyBindingsTests` / `ReaderKeyBindingsTests`
(⌘,), `MainMenuBuilderTests` (items and key equivalents), `SettingsWindowControllerSmokeTests`.

**Previews**: default; Accessibility denied; needs relaunch; recording; conflict; unavailable; reader off;
launch-override note; login item requires approval.

**Scenarios**
- `--present-settings-on-launch`.
- `--scenario settings-hotkey-taken`: `RefusingHotkeyRegistrar` refuses ⌃⌥⌘E and ⌃⌥⌘Y.
- `--scenario settings-needs-relaunch`: `FixedPermissions(accessibility: .granted, eventPosting: .denied)`.
- `--scenario first-launch`: in-memory store with `hasCompletedFirstLaunch = false` and permissions denied.

**`docs/manual-testing.md`, new "Settings" checklist**
- Opening: from the menu, with ⌘, in the editor (empty and with text) and in the pinned reader; on the
  current Space and over a full-screen app; Dock icon and ⌘Tab entry appear; ⌘W / ⎋ close it, the Dock
  icon goes away and focus returns to the previous app.
- Main menu while Settings is open: About, Settings…, Hide, Quit, Edit, Window work; ⌘± and ⌘↩ in the
  editor are not taken by the menu.
- Recorder: recording ⌃⌥⌘T doesn't open the editor; the new combo works at once and the old one doesn't;
  menu titles update; the other slot's combo shows the conflict; ⌥-only and bare letters are refused; ⎋
  cancels; closing while recording restores both shortcuts.
- Reader off: ⌃⌥⌘R does nothing, the menu item is gone, it survives a relaunch, Reset turns it on.
- Text sizes: editor and reader change independently; an existing user's reader size starts at their
  editor size.
- Each other setting takes effect on the next session without a relaunch; clipboard off → the HUD says
  "your clipboard now contains…".
- Accessibility: Grant Access adds LargeText to the list and shows the prompt (after `tccutil reset`);
  revoking while the window is open updates the row within about 1 s.
- First launch (after `defaults delete com.actondon.LargeText` and `tccutil reset`): Settings opens with
  the system prompt over it; the second launch doesn't open Settings.
- Launch-argument and scenario notes show, and nothing reaches `defaults read`.
- Launch at login from an exported build in /Applications: enable, log out and in, `requiresApproval`.

---

## 6. Milestones

1. **M0, refactor with no behaviour change.** `HotkeyBindings` and `ShortcutBinding`; the status item
   reads the reader combo lazily; `PermissionSetup` in `StatusMenuModel`; `SpyHotkeys` refusals.
2. **M1, preference changes.** `readerHotkey: KeyCombo?` with `"off"`; `readerFontSize` with fallback;
   `hasCompletedFirstLaunch`; reader coordinator uses `readerFontSize`. Tests.
3. **M2, Core models.** `ShortcutRules`, `SettingsState`, `SettingsIntent`, `SettingsContext`,
   `PreferenceKey`, hold-threshold clamp. Tests.
4. **M3, coordinator.** `SettingsCoordinator`, its dependencies, `SettingsPresenting`, the logging
   presenter and spies. Tests.
5. **M4, window and main menu, without recorders.** `SettingsWindowController`, `SettingsView`,
   `MainMenuBuilder`, activation-policy switch, "Settings…" item, Grant Access per D6, first-launch flow,
   `--present-settings-on-launch`. All settings except shortcuts work; shortcuts show read-only with Reset
   and Turn off.
6. **M5, ⌘, in the editor and the reader.**
7. **M6, recorders.** `ShortcutRecorderView`, `ShortcutKeyInterpreter`, suspend/apply/rollback,
   `RefusingHotkeyRegistrar`, scenarios, manual checklist.
8. **M7, launch at login.**
9. **M8, docs.** README (Settings, menu, scenarios), `docs/manual-testing.md`, and the "v1 has no settings
   UI" text in `IMPLEMENTATION_PLAN.md` (§2.5 step 5, §2.6, §2.7, §3.9) and `READER_IMPLEMENTATION_PLAN.md`
   (§1, §4.10, §5.4, §10.3). Tell the website about separate text sizes and Settings.

---

## 7. Risks

- **Switching activation policy at runtime** can flash the Dock or leave the window behind the active app
  with cooperative activation. `orderFrontRegardless` is the fallback; check over full-screen apps.
- **Main menu and the panels**: with LargeText active, a menu key equivalent could take a key the editor
  needs. Keep the menu minimal and test ⌘±, ⌘0, ⌘↩.
- **Recorder focus inside SwiftUI**: an `NSViewRepresentable` first responder may fight the `Form`'s focus.
  The AppKit fallback stays open.
- **Silent cross-app conflicts** (spike 0g): the UI can only hint.
- **`SMAppService` from DerivedData** registers the build path.
- **Swift 6 / `ApproachableConcurrency`**: first SwiftUI and `@Observable` code in the package. Keep the
  view model `@MainActor` and pass `SettingsState` as a value.

---

## 8. Open questions

1. ⌘, in the editor with text typed: copy the text to the clipboard (this plan), keep it as a draft that
   comes back next time, or discard it? *Answered by the implementation: both, it copies the text and keeps
   it as the draft, as ⎋ does (§9). Still open for product review.*
2. Should Settings also open on a later launch when Accessibility is missing (for example after the user
   removed it), or strictly the first launch only (this plan)?
3. Should the window show a live text-size sample or a "try the hold threshold" pad?
4. Show the password-manager denylist read-only in v1.1?

---

## 9. Implementation notes

Deviations from the plan above, made while implementing it. The plan text is left as written.

**M0/M1, refactor and preferences**
- `HotkeyBindings` only logs failures; the launch-time notices for an unavailable shortcut stay in
  `AppController`. `HotkeyBindings` is `package`, not internal, so Kit tests can drive it.
- The status menu shows the combos from the last successful `apply`, not the stored preferences.
- A `nil` reader combo is handled when the idle shortcut is pressed; `ReadingSessionCoordinator.startFollowing`
  keeps a defensive, logged guard.
- `InMemoryPreferencesStore.readerFontSize` follows `fontSize` until it is written, like the defaults store.
- `suspend()` unregisters both shortcuts but leaves the bindings' state (combos, `unavailable`) alone.

**M2/M3, Core models and coordinator**
- `ShortcutBinding` also has `unavailableSlots`, which tells the two slots apart when both combos are equal.
- Two more intents, `becameKey` and `resignedKey`, carry the window's key changes. `SpyPermissions` was
  added to TestSupport.
- `loginItemError` is part of `SettingsState`; it is cleared by the next attempt and when the window opens.
- The refresh rebuilds the whole state and sends it only when it changed, so it also picks up font-size
  changes from ⌘± and the login item's status (one `SMAppService` status read per second while visible).
- A validation failure while recording only re-applies the saved combos; nothing is written.
- `resetAll` leaves launch at login and the first-launch flag alone, and keeps the written defaults even
  when the registration of the default shortcuts fails (the row then shows the problem).
- Font sizes are shown clamped to the slider range; the hold threshold is shown as stored.

**M4/M5, window, main menu and ⌘,**
- The main menu's app items (About, Settings…, Hide, Quit) are disabled while an editor or reader panel is
  key, so an unhandled ⌘Q or ⌘H there does nothing, as before the menu existed.
- Both global shortcuts unhide the app before showing a panel.
- ⌘, in the editor with text copies it to the clipboard and also keeps it as the draft, as ⎋ does (§8 Q1).
  *Settings…* in the status menu while the editor is open takes the same path. The HUD reason is
  `.settingsOpened`.
- `hasCompletedFirstLaunch` is set on every launch path, including `--present-on-launch`, which skips the
  first-launch window and prompt.
- Scenarios use a window without a frame autosave name, so not even the frame reaches the real defaults.
- The window counts as visible until it is closed, including while minimised, so the refresh keeps running.

**M6, recorders**
- Tabbing onto a recorder doesn't start recording; a click, Space, Return or the VoiceOver press action does.
- `performKeyEquivalent` is only handled while the recorder is recording and first responder.
- ⎋ when not recording is passed on with `tryToPerform(#selector(cancelOperation(_:)))`, because
  `NSResponder` has no `cancelOperation` to call on `super`.

**M7, launch at login**
- `SMAppServiceLoginItem` reads `SMAppService.mainApp` only inside `status` and `setEnabled`, never in `init`.
- Error mapping (`LoginItemError(registrationError:enabling:)`, pure and tested): "already registered" on
  enable and "job not found" on disable count as success; `EPERM`, `kSMErrorAuthorizationFailure` and
  `kSMErrorLaunchDeniedByUser` become `.notPermitted`; anything else is `.failed(code:)`. An unknown future
  `SMAppService.Status` maps to `.notFound`.
- `AppEnvironment.loginItem` is non-optional (default `InMemoryLoginItem()`), so the row always shows in the
  app; `SettingsDependencies.loginItem` stays optional, and `nil` still hides the row.
- The row is a *Startup* section below Accessibility. *Open Login Items…* shows for `.requiresApproval` and
  after a `.notPermitted` error; `.notFound` gets a note suggesting /Applications.

**M8, docs**
- `IMPLEMENTATION_PLAN.md` and `READER_IMPLEMENTATION_PLAN.md` get short notes and a revision-log entry
  pointing here, instead of rewritten sections.

**Review fixes (after M8)**
- `SettingsWindowController.show` activates on *every* show, not only the first, and `AppActivationSwitch`
  unhides the app first. Otherwise "Settings…" with the window already open (behind another app, or after
  ⌘H) brought it forward without giving it keyboard focus.
- `AppActivationSwitch` follows `NSWorkspace.didActivateApplicationNotification` while Settings is open, so
  closing it returns focus to the app used most recently, not the one that was frontmost when it opened.
- `EditingSessionCoordinator.closeForSettings()` now waits for a session that is already closing (a ⌘↩
  commit still inserting) instead of returning at once, so Settings doesn't activate LargeText while the
  paste is still on its way to the target app.
- `ShortcutRules.reserved` also refuses ⌘H, ⌘M and the edit keys (⌘Z, ⌘⇧Z, ⌘X, ⌘C, ⌘V, ⌘A).
- Known nits left: recording starts even if `makeFirstResponder` fails; app commands in the main menu are
  also disabled while the About panel is key (`keyWindow is NSPanel`); the login-item error mapping
  doesn't check the error domain.
