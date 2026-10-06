# LargeText — Technical Implementation Plan (v1, revision 2)

> Goal of v1: a working, hands-on prototype of the "large text overlay" idea (see `idea.md`) that is
> **architecturally clean** so it can grow once product opinions form. Delivered as a **Swift package**
> that an Xcode AppKit app target imports and starts with a few lines of code.
>
> Revision 2 incorporates an independent review; see §9 for what changed and why.

---

## 1. Feasibility summary

The idea can be built on macOS using only public APIs.

| Concern | Feasible? | API | Permission |
|---|---|---|---|
| Global shortcut while another app is frontmost | Yes | Carbon `RegisterEventHotKey` | **None** |
| Know which app had focus | Yes | `NSWorkspace.frontmostApplication` | None |
| Know which field had focus, read selection | Best effort | AX `kAXFocusedUIElementAttribute`, `kAXSelectedTextAttribute` | Accessibility (`AXIsProcessTrusted`) |
| Show a big editor over everything, incl. full-screen video apps | Yes | Non-activating `NSPanel`, `.fullScreenAuxiliary` | None |
| Put text back into the original field | Yes | Pasteboard + synthesized ⌘V via `CGEvent` (primary) | Event posting (`CGPreflightPostEventAccess`, listed under Accessibility) |
| Press Return after insert (submit search/URL) | Yes | `CGEvent` | Event posting |

**Distribution:** v1 is **non-sandboxed** and distributed via Developer ID and notarization. That is the
simplest path for a prototype. A sandboxed Mac App Store build is *possible*: Magnet, Moom and Paste use AX
and event posting under the sandbox. It brings App Review risk and permission-flow differences, so it is a
PRD-time decision, not a technical impossibility. Hardened Runtime is fine.

**Degraded mode without permission:** the overlay still works. On commit, the text goes to the clipboard and
a large HUD says "Copied — press ⌘V". The app is useful from first launch and asks for permission without
blocking.

**Prior art to compare against during hands-on:** System Settings › Accessibility › Zoom › *Hover Text* →
*Hover Typing* (macOS 14+) shows an enlarged view of the field being typed into. LargeText has to beat it
(full editor, zoom keys, readable from across the room, submit shortcut).

---

## 2. Key technical decisions

### 2.1 Global hotkey: Carbon `RegisterEventHotKey`
- Needs no TCC permission. A `CGEventTap` or a global `NSEvent` monitor would need Input Monitoring or
  Accessibility.
- It is the mechanism mainstream shortcut libraries use, such as `sindresorhus/KeyboardShortcuts`. Our
  wrapper is about 120 lines behind a protocol. A recorder UI can later swap in that library behind the
  same protocol.
- **Default: ⌃⌥⌘T** ("T" for text). ⌃⌥Space was rejected because macOS uses ⌃Space and ⌃⌥Space for
  input-source switching, which conflicts for every multi-language user. Since macOS 15, ⌥-only and ⌥⇧-only
  combos do not work. *Spike:* does `RegisterEventHotKey` return an error, or succeed silently and never
  fire? The error path (status item and notice) depends on the answer.
- Registration failure is surfaced (status item menu shows "Shortcut unavailable" and a notice), never silent.

### 2.2 Overlay window: non-activating `NSPanel` (Spotlight/Raycast style)
- An `NSPanel` subclass created with `[.nonactivatingPanel, .borderless]` **in `init`**. Toggling
  `.nonactivatingPanel` after init is known to be unreliable. `canBecomeKey == true`.
- It becomes key and receives typing **without activating our app**. The target app stays active and its
  field keeps first-responder status, so on close keyboard focus returns to it. This removes most of the
  "restore focus" complexity.
- `level = .statusBar + 1` (tune in the spike). `.screenSaver` was rejected because it would cover system
  permission prompts and our own HUD. `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
  .transient, .ignoresCycle]` keeps the panel visible over full-screen video players on the current Space.
- **Losing key status = cancel, keeping the draft.** This covers ⌘Tab, Spotlight, a click on another display,
  and a notification click. The panel observes `didResignKey` and emits `.lostFocus`, which prevents typing
  into an invisible app behind the overlay.
- A click on the dimmed backdrop also cancels and keeps the draft.
- There is **no activation fallback in v1**. If the spike shows the non-activating approach fails for some
  apps, we add an `ApplicationActivating` port then. It is not designed speculatively.

### 2.3 Text editor: `LargeTextView: NSTextView` in `NSScrollView`
- Multi-line capable. Large font (default 64 pt, range 24–200 pt, step 8 pt). High contrast. Centered card on
  a dimmed backdrop on **the screen that contains the target field**, falling back to the screen with the
  mouse, then the primary screen.
- Plain text only (`isRichText = false`). Smart quotes, smart dashes, autocorrect and text replacement are
  **off**, because the main targets are URL bars and search boxes.
- Prefilled text starts **fully selected**, like a URL bar: typing replaces it and arrow keys edit it.
- **Key handling:** `LargeTextView` overrides `keyDown(with:)` and `performKeyEquivalent(with:)`:
  1. If `hasMarkedText()` is true (IME composition is in progress), pass to `super`. ↩ and ⎋ belong to the
     input method.
  2. Otherwise build a `KeyInput` value (keyCode, characters, modifiers) and ask the pure
     `EditorKeyBindings.action(for:)`.
  3. If an action is returned, emit it. If not, pass to `super`.

  The delegate's `doCommandBy` is *not* used: it cannot distinguish ↩ from ⇧↩ (both are `insertNewline:`) and
  never sees ⌘↩.

  | Key | Action |
  |---|---|
  | ↩ | Commit & insert |
  | ⌘↩ | Commit, insert, then press ↩ in target ("submit") |
  | ⇧↩ / ⌥↩ | Newline |
  | ⎋ | Cancel (keeps draft) |
  | ⌘= / ⌘+ / ⌘- / ⌘0 | Bigger / smaller / reset font size (persisted) |
  | Global hotkey again | Commit & insert (toggle) |

- **Standard editing shortcuts:** Kit installs a minimal *hidden* `NSApp.mainMenu` with an Edit menu (Undo,
  Redo, Cut, Copy, Paste, Select All, Emoji & Symbols). An accessory app's main menu is not displayed, but
  `NSApplication.sendEvent` still routes key equivalents through it while our panel is key. The behavior
  comes from AppKit, not hand-written mappings. *Spike:* verify this. If it fails, map the selectors in
  `EditorKeyBindings`.
- **Committing mid-composition:** before reading the final text, the editor calls
  `inputContext?.discardMarkedText()` (or `unmarkText()`), so a hotkey-toggle commit never inserts
  half-composed text.

### 2.4 Capturing the target
This runs at hotkey time, *before* the panel is shown, with an overall budget of about 150 ms:
1. `NSWorkspace.shared.frontmostApplication` gives pid, bundle id and name (no permission needed). If the
   frontmost app is **LargeText itself** (for example, the permission window is open), skip AX entirely.
   AX calls into our own main thread would block until timeout.
2. Once at startup: `AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)`. This applies
   globally, so a hung target cannot freeze us for long.
3. `AXUIElementCreateApplication(pid)` → `kAXFocusedUIElementAttribute`. This is more reliable for
   Chromium/Electron than the system-wide focused element.
4. A single batched read with `AXUIElementCopyMultipleAttributeValues` gets role, subrole (to detect
   `AXSecureTextField`), selected text, position and size.
5. Convert the frame: AX uses top-left-origin global coordinates. Flip against the **primary screen** (the
   one whose frame origin is 0,0, i.e. `NSScreen.screens.first`), *not* `NSScreen.main`.

Prefill rule for v1: **prefill with the selected text**, if any. This matches paste semantics: pasting
replaces the selection, so "edit selection → commit" replaces exactly what was selected, and "no
selection → commit" inserts at the caret. "Prefill with the whole field value" would need ⌘A before paste
and is deferred.

If no editable element is found (element is nil or not a text role), the overlay still opens. The header
says *"Will copy to clipboard"* and commit uses clipboard-only insertion.

**Secure fields: refuse.** If the focused element is `AXSecureTextField`, we don't open the editor and
instead show a notice: "Password fields aren't supported". Showing a password at 64 pt to the whole room,
and putting it on the clipboard, works against the purpose of a secure field. This is listed as a PRD
question.

### 2.5 Inserting text: strategy pattern
**Pre-insertion guard (prevents pasting into the wrong app).** After the overlay is dismissed, wait up to
about 300 ms until `frontmostApplication.pid == target.pid` and, when AX is available, until the current
focused element `CFEqual`s the captured one. On mismatch or timeout, use clipboard-only insertion with
`reason: .targetChanged`.

**Primary: `PasteboardTextInserter`** (logic in Core, primitives in Platform)
1. **Snapshot** the general pasteboard, within budgets. Skip `dyn.*` and file-promise types. Use a byte
   budget of about 10 MB and a time budget of about 50 ms. If a budget is exceeded, restore is lossy or
   skipped. Snapshotting can be disabled entirely (see the pasteboard-privacy risk in §6).
2. **Write** our string with `clearContents()` and `prepareForNewContents(with: .currentHostOnly)` (no
   Universal Clipboard sync to the iPhone). Also add the `org.nspasteboard.TransientType` and
   `AutoGeneratedType` markers so clipboard managers ignore it.
3. **Wait for modifiers to be released:** Core polls `keystrokes.pressedModifiers` (backed by
   `CGEventSource.flagsState(.hidSystemState)`) through the injected `Sleeper`, with a timeout of about
   300 ms. Otherwise a held ⌃⌥⌘ from the hotkey would turn our ⌘V into ⌃⌥⌘V.
4. **Post a real key sequence:** ⌘↓ V↓ V↑ ⌘↑. Use `CGEventSource(stateID: .privateState)` and explicit
   flags, posted to `.cghidEventTap`. Some apps (Java, VMs, remote desktop) need the modifier events too.
   The key code for "v" is resolved through the **ASCII-capable** layout
   (`TISCopyCurrentASCIICapableKeyboardLayoutInputSource` + `UCKeyTranslate` with ⌘ modifier state). This
   fixes Dvorak, AZERTY and "Dvorak – QWERTY ⌘", and covers Russian or Kana as the current input source.
   Fallback: `kVK_ANSI_V`.
5. **Submit (optional):** post ↩.
6. **Restore:** after about 600 ms, restore the snapshot **only if** `changeCount` is still the one we
   produced. The restore carries no transient markers; clipboard managers may record it again, which is
   acceptable.

**Text transformation before insertion (`InsertionTextPolicy`, pure Core):** if the text has newlines and
the target is single-line (`AXTextField`, `AXSearchField`, `AXComboBox`) or a **terminal** (bundle id in a
known list: Terminal, iTerm2, Ghostty, Warp, …), replace newlines with spaces. Pasting multi-line text into
a shell can *execute commands*. The overlay header shows a small "single-line target" hint.

**Other strategies (same protocol, not in v1):** AX `kAXSelectedTextAttribute` set with read-back
verification; `CGEvent` unicode typing; pressing the target's *Edit › Paste* menu item via AX (does not
depend on layout or modifiers). `ClipboardOnlyTextInserter` (degraded mode) **is** in v1.

### 2.6 Permissions
- Two separate checks, both shown to the user as "Accessibility": `AXIsProcessTrusted()` (reading focus and
  selection) and `CGPreflightPostEventAccess()` (posting ⌘V). `CGEvent.post` fails **silently**, so
  insertion is gated on the preflight check. It is never assumed.
- The permission window opens
  `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` and **polls every 0.5 s
  while visible**. The `com.apple.accessibility.api` notification often fires before the new value is
  readable. It closes itself once access is granted.
- *Spike:* does posting work right after granting, without a relaunch? If not, the window shows a
  "Relaunch LargeText" button.
- `IsSecureEventInputEnabled()` is **only logged** as a diagnostic, never used as a gate. It reports any
  process's secure input, and stale holders are common.

### 2.7 App shell
- Accessory app: `LSUIElement = YES` in the Xcode app's Info.plist, plus
  `NSApp.setActivationPolicy(.accessory)` defensively.
- `NSStatusItem` menu: *Open Large Editor (⌃⌥⌘T)*, *Permission: Granted ✓ / Grant Access…*, the hotkey
  error if any, *Quit*.
- Hidden main menu (§2.3).

---

## 3. Architecture

### 3.1 Principles
- **Unidirectional flow.** One coordinator owns session state. Views emit *intents*, and the coordinator
  pushes *presentation state* back. **Exception, by design:** the text view owns the text being edited
  during a session (§3.5). Round-tripping keystrokes would destroy the caret, undo and IME state.
- **Every side effect behind a protocol (a "port").** This covers hotkeys, focus capture, pasteboard, key
  posting, permissions, preferences, time, presentation and system events. Live adapters live in Platform
  and UI. Fakes live in test support and debug scenarios.
- **Single composition root.** Concrete live types are created only in Kit's `AppEnvironment`, which is what
  makes it possible to launch the app in a chosen state.
- **Live adapters have no side effects in `init`.** No observers, prompts or Carbon handler installs in
  `init`; those happen in an explicit `start()` or on first use. That makes it safe to build an
  environment and then replace parts of it.
- **Pure core.** Domain logic imports only Foundation, so unit tests are fast and deterministic.
- **Swift 6 language mode, strict concurrency, main-actor by design.** AppKit, AX and the pasteboard are all
  used on the main actor, so ports are declared `@MainActor protocol …` explicitly and models don't need to
  be `Sendable`. No `@unchecked Sendable` anywhere.
- **Access control:** cross-module API uses Swift's **`package`** access level. Only Kit's facade is `public`.
- **No third-party dependencies** in v1.

### 3.2 Package layout & module graph

```
LargeText/                              swift-tools-version 6.0, platforms: [.macOS(.v14)]
├── Package.swift
├── Sources/
│   ├── LargeTextCore/                  Models, ports, coordinator, policies, inserters. Foundation only.
│   ├── LargeTextPlatform/              Live adapters: Carbon, AX, NSPasteboard, CGEvent, TIS, UserDefaults, NSWorkspace.
│   ├── LargeTextUI/                    AppKit: overlay panel, editor, HUD, status item, permission window, #Previews.
│   └── LargeTextKit/                   Composition root + public facade + Scenarios/ (#if DEBUG). The Xcode app imports this only.
└── Tests/
    ├── LargeTextTestSupport/           Spies, recorders & fakes for every port. Linked by test targets only.
    ├── LargeTextCoreTests/             Coordinator state machine, inserters, policies.
    ├── LargeTextPlatformTests/         Pure helpers: AX geometry, snapshot filtering, key-code resolution.
    ├── LargeTextUITests/               EditorKeyBindings, ScreenResolver.
    └── LargeTextKitTests/              LaunchConfiguration parsing, scenario wiring.
```

```
                 ┌────────────────┐
                 │  LargeTextKit  │  composition root · public facade · debug scenarios
                 └──┬──────────┬──┘
           ┌────────▼──┐    ┌──▼───────┐
           │ Platform  │    │    UI    │      (never import each other)
           └────────┬──┘    └──┬───────┘
                 ┌──▼──────────▼──┐
                 │      Core      │  ◀── TestSupport ◀── *Tests
                 └────────────────┘
```

`LargeTextTestSupport` is declared as a regular target under `Tests/`, but **no product depends on it**, so
it never ships. Debug scenarios use small stubs inside `LargeTextKit/Scenarios/`, wrapped in `#if DEBUG`.
Xcode builds package targets with `DEBUG` in the Debug configuration, so the stubs compile out of Release.

### 3.3 Core models (`LargeTextCore`)

```swift
// Input
struct Modifiers: OptionSet, Hashable, Codable { command, option, control, shift }
struct KeyCombo: Hashable, Codable { var keyCode: UInt32; var modifiers: Modifiers }   // Carbon key code
enum Keystroke: Equatable { case paste, returnKey }

// Target
struct TargetApplication: Equatable { let processIdentifier: Int32; let bundleIdentifier: String?; let localizedName: String }
enum ElementKind: Equatable { case singleLineText, multiLineText, secureText, unknownEditable, notEditable }
/// Opaque platform element (AXUIElement in production). Identity is decided by the port that created it.
struct ElementHandle { let raw: AnyObject }
struct FocusTarget {
    let application: TargetApplication?        // nil when LargeText itself was frontmost
    let element: ElementHandle?
    let elementKind: ElementKind?              // nil = unknown (no AX permission / not found)
    let selectedText: String?
    let frame: CGRect?                         // AppKit global coordinates (already flipped)
}

// Session
struct EditingSession: Identifiable { let id: UUID; let target: FocusTarget; let initialText: String }
struct Draft: Equatable { let text: String; let savedAt: Date }   // recovered if reopened within 60 s

enum CommitMode: Equatable { case insert, insertAndSubmit }
enum CancelReason: Equatable { case userCancelled, lostFocus, targetTerminated, sessionResigned }
enum InsertionMethod: Equatable { case pasteboard, clipboardOnly }
enum InsertionFallbackReason: Equatable { case permissionMissing, noEditableTarget, targetChanged }
enum InsertionOutcome: Equatable { case inserted(InsertionMethod); case copiedToClipboard(InsertionFallbackReason) }

// Presentation
struct FontSize: Equatable { let points: Double }
enum ZoomStep: Equatable { case bigger, smaller, reset }
enum Notice: Equatable {
    case copiedToClipboard(InsertionFallbackReason)
    case secureFieldUnsupported
    case hotkeyUnavailable(KeyCombo)
    case permissionNeeded
}

// Pasteboard
struct PasteboardSnapshot: Equatable { struct Item: Equatable { var dataByType: [String: Data] }; var items: [Item]; var isComplete: Bool }

enum PermissionStatus: Equatable { case granted, denied }
struct Permissions: Equatable { var accessibility: PermissionStatus; var eventPosting: PermissionStatus }
```
(These are `package` types. Bodies are shown abbreviated.)

### 3.4 Ports (protocols) in Core

All are `@MainActor`. Each has one live implementation (Platform or UI) and fakes (TestSupport, and Kit
scenarios where needed).

```swift
// ── Input ──────────────────────────────────────────────────────────────
@MainActor protocol HotkeyRegistering: AnyObject {
    /// Throws HotkeyError.unavailable when the system refuses the combo.
    func register(_ combo: KeyCombo, handler: @escaping @MainActor () -> Void) throws -> any HotkeyRegistration
}
@MainActor protocol HotkeyRegistration: AnyObject { func unregister() }

/// System events that end a session: target app terminated/deactivated, screen lock, sleep.
@MainActor protocol SystemEventsObserving: AnyObject {
    func events() -> AsyncStream<SystemEvent>          // .applicationTerminated(pid), .applicationActivated(pid), .sessionResigned
}

// ── Reading the world ──────────────────────────────────────────────────
@MainActor protocol FocusCapturing: AnyObject {
    func captureFocus() -> FocusTarget
    /// Pre-insertion guard: is `target` still the frontmost app / focused element?
    func isStillFocused(_ target: FocusTarget) -> Bool
}
@MainActor protocol PermissionsProviding: AnyObject {
    var current: Permissions { get }                   // always a fresh read
    func requestAccessibility()                         // shows the system prompt
    func openSystemSettings()
}

// ── Acting on the world ────────────────────────────────────────────────
@MainActor protocol PasteboardClient: AnyObject {
    var changeCount: Int { get }
    func snapshot(budget: SnapshotBudget) -> PasteboardSnapshot
    func restore(_ snapshot: PasteboardSnapshot)
    @discardableResult func writeTransientString(_ string: String) -> Int   // returns the new changeCount
}
@MainActor protocol KeystrokeSending: AnyObject {
    var pressedModifiers: Modifiers { get }            // physical state (HID)
    func send(_ stroke: Keystroke)
}
@MainActor protocol TextInserting: AnyObject {
    func insert(_ text: String, into target: FocusTarget, mode: CommitMode) async -> InsertionOutcome
}

// ── State & time ───────────────────────────────────────────────────────
@MainActor protocol PreferencesStore: AnyObject {      // class-bound: one shared instance, no copy bugs
    var fontSize: FontSize { get set }
    var hotkey: KeyCombo { get set }
}
protocol Sleeper: Sendable { func sleep(for duration: Duration) async throws }
protocol DateProviding { var now: Date { get } }      // draft expiry

// ── Presentation (implemented in LargeTextUI) ─────────────────────────
@MainActor protocol OverlayPresenting: AnyObject {
    /// `initialText` is applied once; afterwards the text view owns the text.
    func present(sessionID: UUID, initialText: String, selectInitialText: Bool,
                 chrome: OverlayChrome, intents: @escaping @MainActor (OverlayIntent) -> Void)
    func update(_ chrome: OverlayChrome)               // never touches the text
    func requestCommit(mode: CommitMode)               // hotkey-toggle: view emits the normal .commit intent
    /// Returns once the panel is ordered out, with the text at that moment (used for drafts).
    @discardableResult func dismiss() async -> String
}
@MainActor protocol NoticePresenting: AnyObject { func show(_ notice: Notice) }
```

```swift
/// Everything the overlay draws *except* the text being edited.
struct OverlayChrome: Equatable {
    var fontSize: FontSize
    var targetName: String?              // "Typing into Safari"
    var targetBundleIdentifier: String?  // UI resolves the icon via NSWorkspace; Core never sees NSImage
    var targetFrame: CGRect?             // UI picks the screen
    var hint: TargetHint?                // .willCopyToClipboard, .singleLine
}

/// Every intent is tagged with the session that produced it; stale intents are ignored.
struct OverlayIntent: Equatable {
    let sessionID: UUID
    let kind: Kind
    enum Kind: Equatable {
        case commit(CommitMode, text: String)  // final text travels with the commit
        case cancel(text: String)              // text kept as draft
        case lostFocus(text: String)           // panel resigned key
        case zoom(ZoomStep)
    }
}
```

### 3.5 The coordinator: `EditingSessionCoordinator` (Core)

This is a small explicit state machine with no AppKit. It is fully unit-tested with fakes.

```swift
@MainActor
final class EditingSessionCoordinator {
    enum Phase: Equatable { case idle, editing(sessionID: UUID), finishing(sessionID: UUID) }

    private(set) var phase: Phase = .idle               // session details kept in a private property
    func phases() -> AsyncStream<Phase>                  // multi-subscriber: status item, tests

    init(dependencies: CoreDependencies)
    func start()                                         // subscribes to SystemEventsObserving
    func toggle()                                        // hotkey & menu entry point
}

struct CoreDependencies {                                // the ONLY things the coordinator knows
    var focus: any FocusCapturing
    var inserter: any TextInserting
    var overlay: any OverlayPresenting
    var notices: any NoticePresenting
    var preferences: any PreferencesStore
    var systemEvents: any SystemEventsObserving
    var clock: any DateProviding
}
```

**Transition table** (each row is a unit test):

| Phase | Event | Effect → next phase |
|---|---|---|
| idle | `toggle()`, target is a secure field | notice `.secureFieldUnsupported` → idle |
| idle | `toggle()` | capture focus; initial text = selection ?? fresh draft (< 60 s) ?? "" → present → **editing** |
| editing | `toggle()` | ask the overlay to commit (the overlay emits `.commit(.insert, text)`) |
| editing | `.commit(mode, text)`, text is whitespace-only | same as cancel, without saving a draft |
| editing | `.commit(mode, text)` | **finishing**: `await dismiss()` → `await inserter.insert` → notice if degraded → clear draft → **idle** |
| editing | `.cancel(text)` / `.lostFocus(text)` | save draft → `await dismiss()` → **idle** |
| editing | system event: target terminated / session resigned | `text = await dismiss()` → save draft → **idle** |
| editing | `.zoom(step)` | `FontSizePolicy.apply`, persist, `overlay.update(chrome)` → editing |
| finishing | anything | ignored |
| any | intent with a stale `sessionID` | ignored |

"Toggle while editing commits" needs the text, which the view owns. `requestCommit(mode:)` makes the view
emit the normal `.commit` intent, so commit always follows a single code path. Likewise, `dismiss()`
returns the current text, so cancellations caused by system events can still save a draft.

Permission revoked mid-session needs no special case: the inserter checks permissions at commit time.

### 3.6 Insertion composition (logic in Core, primitives in Platform)

```swift
final class PasteboardTextInserter: TextInserting {        // Core
    init(pasteboard: any PasteboardClient, keystrokes: any KeystrokeSending,
         focus: any FocusCapturing, sleeper: any Sleeper, timing: InsertionTiming = .default)
}
final class ClipboardOnlyTextInserter: TextInserting { … } // Core
final class RoutingTextInserter: TextInserting {           // Core: chooses per call
    init(permissions: any PermissionsProviding,
         pasteboard: any TextInserting, clipboardOnly: any TextInserting)
    // posting denied → clipboardOnly(.permissionMissing)
    // target.application == nil or elementKind == .notEditable → clipboardOnly(.noEditableTarget)
    // else → pasteboard (which itself may degrade to .targetChanged)
}
enum InsertionTextPolicy { static func prepare(_ text: String, for target: FocusTarget) -> String }  // newline rule
struct InsertionTiming { focusReturnTimeout, modifierReleaseTimeout, pollInterval, restoreDelay }
```

All the tricky ordering (guard → snapshot → write → wait for modifiers → ⌘V → ↩ → delayed conditional
restore) is tested in Core with a fake pasteboard, a recording keystroke sender and an immediate sleeper.
Platform contains only thin adapters.

### 3.7 Live adapters (`LargeTextPlatform`)

| Type | Implements | Notes |
|---|---|---|
| `CarbonHotkeyRegistrar` | `HotkeyRegistering` | Installs one `InstallEventHandler` lazily on first `register`. The C callback gets `Unmanaged` self and calls `MainActor.assumeIsolated`, because Carbon dispatches on the main thread. |
| `AccessibilityFocusCapturer` | `FocusCapturing` | §2.4. Pure helpers: `AXGeometry.appKitRect(axPosition:axSize:primaryScreenFrame:)` and `ElementKind(role:subrole:)`. |
| `SystemPermissionsProvider` | `PermissionsProviding` | `AXIsProcessTrusted`, `CGPreflightPostEventAccess`, `AXIsProcessTrustedWithOptions(prompt)`. |
| `SystemPasteboardClient` | `PasteboardClient` | Takes an `NSPasteboard` in `init` (`.general` in live, a named private board in tests). Type filtering via a pure `SnapshotTypeFilter`. |
| `CGEventKeystrokeSender` | `KeystrokeSending` | `KeyboardLayoutResolver` (TIS/UCKeyTranslate, ASCII-capable layout) and `.privateState` source. |
| `WorkspaceSystemEvents` | `SystemEventsObserving` | `NSWorkspace` notifications: `didTerminateApplication`, `didActivateApplication`, `sessionDidResignActive`, `screensDidSleep`. |
| `UserDefaultsPreferencesStore` | `PreferencesStore` | Keys namespaced `LargeText.*`. `InMemoryPreferencesStore` (class) lives in Core. |
| `TaskSleeper`, `SystemClock` | `Sleeper`, `DateProviding` | |

### 3.8 UI (`LargeTextUI`)

| Type | Role |
|---|---|
| `OverlayPanel: NSPanel` | Non-activating (set in init), borderless, key-capable, full-screen-auxiliary. Posts resign-key. |
| `OverlayWindowController` | Implements `OverlayPresenting`. Picks the screen via `ScreenResolver`, owns panel and editor, fades ≤120 ms (respects *Reduce Motion*), and turns resign-key / backdrop click into `.lostFocus` / `.cancel`. |
| `EditorViewController` | Backdrop, card, header (icon + "Typing into Safari" + hint), `LargeTextView`, footer hints. Renders `OverlayChrome` and emits intents. No business logic. |
| `LargeTextView: NSTextView` | Key interception per §2.3 and marked-text handling. |
| `EditorKeyBindings` | Pure: `(KeyInput) -> EditorAction?`. `KeyInput` is a small value type built from `NSEvent`. Unit-tested. |
| `ScreenResolver` | Pure: `(targetFrame, mouseLocation, [ScreenDescriptor]) -> ScreenDescriptor`. Unit-tested. |
| `HUDNoticePresenter` | Implements `NoticePresenting`: a large rounded HUD that auto-hides after 2.5 s. |
| `StatusItemController` | Menu bar item. Consumes `coordinator.phases()` and permission state. |
| `PermissionWindowController` | Explanation, "Open System Settings", 0.5 s polling while visible, optional "Relaunch". |
| `Theme` | All colors and metrics in one place. |
| `#Preview`s | Previews of `EditorViewController` in typical states (empty, prefilled, long text, single-line hint). This is the fast UI-iteration loop. |

Overlay visuals (v1, deliberately simple; to be tuned after hands-on):
- Backdrop: black at 55% alpha over the chosen screen.
- Card: about 80% of screen width, `NSVisualEffectView` (`.hudWindow`), corner radius 24.
- Header: app icon + "Typing into Safari", at 0.4× the editor font.
- The editor grows up to 60% of screen height, then scrolls.
- Footer: `↩ Insert   ⌘↩ Insert & Submit   ⎋ Cancel   ⌘± Size`, at 0.3× the editor font.

### 3.9 Composition root & running in a given state (`LargeTextKit`)

```swift
@MainActor
public struct AppEnvironment {                       // service factories; nothing is created until used
    var makeHotkeys:      () -> any HotkeyRegistering
    var makeFocus:        () -> any FocusCapturing
    var makePermissions:  () -> any PermissionsProviding
    var makePasteboard:   () -> any PasteboardClient
    var makeKeystrokes:   () -> any KeystrokeSending
    var makeSystemEvents: () -> any SystemEventsObserving
    var makePreferences:  () -> any PreferencesStore
    var makeOverlay:      () -> any OverlayPresenting
    var makeNotices:      () -> any NoticePresenting
    var sleeper: any Sleeper
    var clock: any DateProviding

    public static var live: AppEnvironment { get }
}

public struct LaunchConfiguration: Equatable {
    public var scenario: Scenario?                   // `--scenario <name>` or LARGETEXT_SCENARIO=<name>
    public var presentOnLaunch: Bool                 // `--present-on-launch`
    public static var current: LaunchConfiguration { get }   // from ProcessInfo
    init(arguments: [String], environment: [String: String])  // pure, unit-tested
}

public enum Scenario: String, CaseIterable {         // the list itself always exists; stubs are #if DEBUG
    case overlayEmpty        = "overlay-empty"          // stub target "Safari"
    case overlayPrefilled    = "overlay-prefilled"      // selection "https://www.apple.com"
    case overlayLongText     = "overlay-long-text"
    case singleLineTarget    = "single-line-target"     // multi-line text → newline policy visible
    case noEditableTarget    = "no-editable-target"     // header: "Will copy to clipboard"
    case secureTarget        = "secure-target"          // refusal notice
    case permissionMissing   = "permission-missing"     // degraded mode HUD
    case targetLost          = "target-lost"            // guard fails → .targetChanged HUD
    case hotkeyUnavailable   = "hotkey-unavailable"
    case loggingInsertion    = "logging-insertion"      // real hotkey & focus; insertion only logs
}

extension AppEnvironment {
    /// live, with the scenario's overrides applied. In Release builds scenarios are ignored (with a log line).
    public static func resolve(_ launch: LaunchConfiguration) -> AppEnvironment
}
```

Scenario rules:
- A scenario replaces **only the factories it needs**. For example, `permissionMissing` replaces
  `makePermissions` with a denied stub, and `overlayPrefilled` replaces `makeFocus` and the inserter's
  pasteboard and keystrokes with logging stubs.
- Scenarios always use `InMemoryPreferencesStore`, so they never change real settings.
- Usage: add Xcode schemes with *Arguments Passed On Launch* `--scenario overlay-prefilled --present-on-launch`.
  `#Preview`s cover the purely visual iteration.

Public facade, the only API the Xcode app uses:

```swift
@MainActor
public final class LargeTextApplication {
    public init(environment: AppEnvironment, launch: LaunchConfiguration)
    public convenience init(launch: LaunchConfiguration = .current)   // = resolve(launch)
    public func start()   // activation policy, hidden main menu, status item, hotkey, coordinator, permission prompt
    public func stop()
}
```

The complete code of the Xcode app (created by you later):

```swift
import AppKit
import LargeTextKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let app = LargeTextApplication(launch: .current)
    func applicationDidFinishLaunching(_ notification: Notification) { app.start() }
}
```
Xcode app settings: `LSUIElement = YES`, **App Sandbox capability removed**, Hardened Runtime on, signed
with your development team (see §6 on TCC and signing).

### 3.10 Data flow: one complete commit

```
User ⌃⌥⌘T
  └─▶ CarbonHotkeyRegistrar ─▶ coordinator.toggle()
        ├─ focus.captureFocus()      → FocusTarget{Safari, .singleLineText, selection:"apple.com", frame}
        ├─ phase = .editing(id)
        └─ overlay.present(id, initialText:"apple.com", selectInitialText:true, chrome{64pt,"Safari"}, intents)
User types (text lives in LargeTextView), presses ⌘+
  └─▶ EditorKeyBindings → .zoom(.bigger) ─▶ coordinator → prefs.fontSize = 72 → overlay.update(chrome)
User presses ⌘↩
  └─▶ discardMarkedText → intent(id, .commit(.insertAndSubmit, "apple.com/mac")) ─▶ coordinator
        ├─ phase = .finishing(id)
        ├─ await overlay.dismiss()                   (Safari never stopped being active)
        ├─ await inserter.insert(text, target, .insertAndSubmit)
        │     Routing → Pasteboard:
        │       guard isStillFocused (poll ≤300ms) → InsertionTextPolicy → snapshot → writeTransient →
        │       wait modifiers up → ⌘↓V↓V↑⌘↑ → ↩ → sleep 600ms → restore if changeCount unchanged
        ├─ outcome .inserted → clear draft
        └─ phase = .idle
```

---

## 4. Testing strategy

- **Swift Testing** (`import Testing`) throughout.
- **Core (highest value):** every row of the §3.5 transition table, including stale session ids, draft
  save/restore/expiry, whitespace commit, and `requestCommit` on toggle. `PasteboardTextInserter` ordering,
  guard failure, modifier-wait timeout, conditional restore, incomplete snapshot. `RoutingTextInserter`
  choices. `InsertionTextPolicy` and `FontSizePolicy`.
- **UI pure functions:** `EditorKeyBindings` (↩ vs ⇧↩ vs ⌘↩, zoom keys, Escape) and `ScreenResolver`.
- **Platform pure helpers:** AX geometry flip against a non-zero-origin secondary screen, `SnapshotTypeFilter`,
  `ElementKind` mapping, pasteboard round trip on `NSPasteboard(name:)` (never `.general`).
- **Kit:** `LaunchConfiguration` parsing, and that each scenario overrides exactly the expected factories.
- **Manual matrix** (`docs/manual-testing.md`): Safari URL bar, Chrome omnibox, Firefox, TextEdit, Notes,
  Slack/VS Code (Electron), Terminal/iTerm (multi-line policy), a password field (refusal), full-screen video
  in Safari/QuickTime, two displays, Dvorak and Russian layouts, Japanese IME (compose, then ↩, then commit),
  ⌘Tab while the overlay is open, target app quitting while the overlay is open.
- **Instrumentation:** an `os.Logger` + signpost trace per session (capture duration, dismiss→focus-return
  time, paste time, restore result). This feeds the PRD with real numbers.

---

## 5. Milestones

0. **Spike (half a day, throwaway branch).** Verify the risky assumptions:
   - a) the non-activating panel gets typing; focus returns to Safari/Chrome/Electron fields after `orderOut`;
     measure that delay;
   - b) the panel appears over a full-screen video Space at `.statusBar + 1`;
   - c) ⌘V via `CGEvent` lands in the Chrome omnibox; compare `postToPid` with the HID tap;
   - d) hidden main menu routes ⌘C/⌘V/⌘Z in the panel;
   - e) IME, Character Viewer (⌃⌘Space) and Dictation inside the panel;
   - f) ⌘Tab, Spotlight and resign-key behavior;
   - g) hotkey registration failure mode (⌥-only), hotkey firing under Secure Input;
   - h) pasteboard privacy prompt behavior on the macOS version you're running now;
   - i) permission granted mid-run, with and without a relaunch.
1. **Package skeleton.** `Package.swift`, four library targets, test support, Core models and ports, empty
   tests passing.
2. **Vertical slice (fast "feel").** Minimal real implementations end-to-end: Carbon hotkey → focus capture
   → panel with editor → pasteboard insertion → status item. Rough visuals, but the real architecture. *You
   can start using it here.*
3. **Core hardening.** The complete transition table, drafts, routing, text policy, guard, and full Core
   tests.
4. **UI polish.** Theme, header/footer, HUD, permission window, `#Preview`s, Reduce Motion, multi-display.
5. **Kit.** Debug scenarios and Xcode scheme instructions, `LaunchConfiguration` tests, the manual-testing
   checklist.
6. **Hands-on.** Run the manual matrix and collect opinions for the PRD.

Out of scope for v1: hotkey recorder and settings window, theme customization, prefill with the whole field,
per-app insertion strategy, entry history, launch at login (`SMAppService.mainApp`), Sparkle updates,
activation fallback, MAS sandbox build.

---

## 6. Risks & mitigations

| Risk | Mitigation |
|---|---|
| ⌘V lands in the wrong app (focus moved) | Resign-key cancels; pre-insertion guard on pid and focused element; fallback to clipboard plus HUD. |
| Non-activating panel misbehaves in some app | Spike 0a. If confirmed, add an activation port then. |
| Paste races (target reads pasteboard late) | 600 ms restore delay, conditional on `changeCount`; the timing struct is injectable and can become a preference later. |
| **Pasteboard privacy** (macOS 15.4+ preview of programmatic-read prompts via `NSPasteboard.accessBehavior`; enforcement announced as upcoming) | Spike 0h. `SnapshotBudget.disabled` mode: overwrite the clipboard without restoring, and say so in the HUD. |
| Snapshot forces lazy or promised data from the source app (slow, large) | Type filter, byte and time budgets, lossy restore allowed. |
| Clipboard managers / Universal Clipboard sync our text | Transient markers + `.currentHostOnly`. |
| Physical modifiers still held when posting | HID-state wait, `.privateState` source, explicit flags, full ⌘ down/up sequence. |
| Non-QWERTY / non-Latin layouts | ASCII-capable layout key-code resolution. |
| Multi-line paste executes commands in terminals | `InsertionTextPolicy` newline rule + header hint. |
| Hung target app blocks AX | Global 0.25 s messaging timeout, batched attribute read, 150 ms capture budget, AX skipped for our own pid. |
| Hotkey conflicts / ⌥-only combos rejected (macOS 15) | Default ⌃⌥⌘T; registration errors surfaced in the status item and a notice. |
| `IsSecureEventInputEnabled` false positives | Diagnostic only, never a gate. |
| **TCC permission resets during development** | Sign Debug with your real team identity (not "Sign to Run Locally"). Never change the bundle id or signing identity between builds, because TCC keys on the designated requirement. After an intentional change, run `tccutil reset Accessibility <bundle id>` once. |

---

## 7. Coding conventions

- Swift 6 language mode. `@MainActor` declared explicitly on ports and UI and coordination types. No
  `DispatchQueue.main.async` scattered around.
- One primary type per file. Feature folders inside each module (`Hotkey/`, `Focus/`, `Insertion/`,
  `Overlay/`, `Permissions/`, `Preferences/`).
- `package` for cross-module API. `public` only for Kit's facade (`LargeTextApplication`, `AppEnvironment`,
  `LaunchConfiguration`, `Scenario`).
- Logging with `os.Logger(subsystem: "LargeText", category: <module>)`. Signposts for the session trace.
- Process-wide singletons (`NSPasteboard.general`, `NSWorkspace.shared`, `NSApp`) are referenced only in
  Platform/UI adapters and the composition root.
- Typed `enum` errors. User-visible failures always become a `Notice`, never silent.

---

## 8. Open questions for the PRD (to answer after hands-on)

- Hotkey choice, and whether a second "insert & submit" hotkey is needed.
- Overlay style: full-screen dim vs. a floating card only; theme; default size.
- Prefill: selection only vs. the whole field.
- Secure fields: keep refusing, or offer a "masked large" mode?
- Pasteboard restore: always, never, or configurable (also depends on macOS privacy prompts).
- Newline handling per target: automatic vs. user choice.
- Draft history beyond the 60 s recovery.
- Distribution: Developer ID only, or also the Mac App Store (sandbox)?

---

## 9. Revision log (review findings → changes)

| Finding | Change |
|---|---|
| ⌃⌥Space conflicts with input-source switching | Default is now ⌃⌥⌘T; registration-failure path specified (§2.1). |
| ⌘V could land in the wrong app | Resign-key → `.lostFocus`; system-event observation; pre-insertion guard (§2.2, §2.5, §3.5). |
| Round-tripping text through the coordinator breaks caret/undo/IME | The text view owns the text; `OverlayChrome` split out; commit carries the text; `discardMarkedText` (§2.3, §3.4). |
| `doCommandBy` can't distinguish ↩/⇧↩ or see ⌘↩ | `LargeTextView` key interception + pure `EditorKeyBindings` (§2.3). |
| `Phase: Equatable` wouldn't compile; implicit `@MainActor` | Phase holds ids only; explicit `@MainActor protocol`s; no `Sendable` on main-actor models (§3.3–3.5). |
| Sandbox claim was too strong | Reworded as a v1 choice, with MAS left possible (§1). |
| Posting permission ≠ AX trust; notification timing | Two checks, preflight gating, polling, relaunch spike (§2.6). |
| Pasteboard snapshot cost, privacy prompts, Universal Clipboard | Budgets, type filter, disable mode, `.currentHostOnly` (§2.5, §6). |
| AX capture could block | Global timeout, app-element query, batched reads, own-pid skip, capture budget (§2.4). |
| Coordinate flip must use the primary screen | Explicit in the helper signature and tests (§2.4, §3.7). |
| Modifier/layout details | HID-state polling in Core via a port; full key sequence; ASCII-capable layout (§2.5). |
| Secure Input global flag | Diagnostic only (§2.6). |
| `.screenSaver` level too high | `.statusBar + 1` (§2.2). |
| Edit-menu routing | Hidden main menu, with a manual-mapping fallback (§2.3). |
| `PreferencesStore` value-copy bug | Class-bound protocol; unused `insertionMethod` preference dropped (§3.4). |
| `Cancellable` undefined, single `onPhaseChange` | `AsyncStream`s; permission observation replaced by fresh reads + polling (§3.4, §3.5). |
| Six targets, all `public`, Demo executable misleading | Four library targets; `package` access; Demo removed in favor of `#Preview` + Xcode schemes; TestSupport test-only; scenarios `#if DEBUG` (§3.2, §3.9). |
| `live()` + override needs side-effect-free init; `startup` isn't a service | Per-service factories; `LaunchConfiguration.presentOnLaunch`; explicit `.current` (§3.1, §3.9). |
| Missing transitions | Full transition table, including stale ids, lock/sleep and target termination (§3.5). |
| Multi-line paste into shells / single-line fields | `InsertionTextPolicy` (§2.5). |
| Milestones built bottom-up, so "feel" comes late | Vertical slice right after the skeleton; spike extended (§5). |
| Nice-to-haves | Draft recovery, prefill selected, icon via bundle id, refuse secure fields, menu-press strategy noted, `ApplicationActivating` removed, all types defined, signpost trace, Hover Typing baseline, signing note. |
