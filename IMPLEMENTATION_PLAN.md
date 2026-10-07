# LargeText — Technical Implementation Plan (v1, revision 4)

> Goal of v1: a working, hands-on prototype of the "large text overlay" idea (see `idea.md`) that is
> **architecturally clean** so it can grow once product opinions form. Delivered as a **Swift package**
> that an Xcode AppKit app target imports and starts with two lines of code.
>
> Revision 4 incorporates three independent review rounds; see §9.

---

## 1. Feasibility summary

The idea can be built on macOS with public APIs only.

| Concern | Feasible? | API | Permission |
|---|---|---|---|
| Global shortcut while another app is frontmost | Yes | Carbon `RegisterEventHotKey` | **None** |
| Know which app had focus | Yes | `NSWorkspace.frontmostApplication` | None |
| Know which field had focus, read selection | Best effort | AX `kAXFocusedUIElementAttribute`, `kAXSelectedTextAttribute` | Accessibility (`AXIsProcessTrusted`) |
| Show a big editor over everything, incl. full-screen video apps | Yes | Non-activating `NSPanel`, `.fullScreenAuxiliary` | None |
| Put text back into the original field | Yes | Pasteboard + synthesized ⌘V via `CGEvent` | Event posting (`CGPreflightPostEventAccess`, shown under Accessibility) |
| Press Return after insert (submit search/URL) | Yes | `CGEvent` | Event posting |

**Distribution:** v1 is **not sandboxed** and is distributed with Developer ID and notarization. That is the
simplest path for a prototype. A sandboxed Mac App Store build is *possible*: Magnet, Moom and Paste use AX
and event posting from the sandbox. It brings App Review risk and a different permission flow, so the
decision belongs to the PRD and is not a technical blocker. Hardened Runtime is fine.

**Degraded mode without permission:** the overlay still works. On commit the text goes to the clipboard and
a large HUD says "Copied — press ⌘V".

**Prior art to compare against during hands-on:** Accessibility › Zoom › *Hover Text* → *Hover Typing*
(macOS 14+). It shows an enlarged view of the field being typed into. LargeText must beat it: a full editor,
zoom keys, readable from across the room, and a submit shortcut.

---

## 2. Key technical decisions

### 2.1 Global hotkey: Carbon `RegisterEventHotKey`
- Needs no TCC permission. Used by mainstream libraries (e.g. `sindresorhus/KeyboardShortcuts`), and it can
  later sit behind the same protocol if we want a recorder UI. Our own wrapper is about 120 lines.
- **Default: ⌃⌥⌘T.** ⌃⌥Space conflicts with input-source switching. Since macOS 15, ⌥-only and ⌥⇧-only
  combos are refused.
- **Ownership:** Kit registers the hotkey in `LargeTextApplication.start()` and wires it to
  `coordinator.toggle()`. The coordinator never sees hotkeys.
- **Registration failure** shows a notice and a "Shortcut unavailable" item in the status menu. *Spike 0g*
  decides how failure is detected: `RegisterEventHotKey` might return an error, or it might silently never fire.

### 2.2 Overlay window: non-activating `NSPanel` (Spotlight/Raycast style)
- An `NSPanel` subclass created with `[.nonactivatingPanel, .borderless]` **in `init`**, with
  `canBecomeKey == true`.
- It becomes key and receives typing **without activating our app**. The target app stays active and its
  field keeps first responder. When the overlay closes, keyboard focus returns to that field.
- `level = .statusBar + 1` and `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient,
  .ignoresCycle]`. This keeps the overlay above full-screen video on the current Space. It also sits above
  modal system prompts, so **we never trigger a permission prompt while a session is active**.
- **Resign-key rule:** *any* resign-key that our own `dismiss()` did not cause emits
  `.cancel(.lostFocus)`, and the draft is kept. This covers ⌘Tab, Spotlight, clicks on another display,
  screen lock and sleep. Once a programmatic dismiss starts, the controller stops emitting intents.
- Clicking the dimmed backdrop emits `.cancel(.userCancelled)`, and the draft is kept.
- The backdrop covers `screen.frame`, including that screen's menu bar. With a second display, the other
  screen's status item is still reachable. Its *Open Large Editor* action calls `toggle()`, which commits,
  exactly like the hotkey. No special state is needed.
- The HUD is a separate **non-key** `NSPanel` with the same level and `collectionBehavior` as the overlay.
  It is therefore visible over full-screen video and never steals key status.
- **Known limitation:** clicking into the Character Viewer (⌃⌘Space) makes another process key, so the
  session cancels with the draft kept. IME candidate windows and Dictation do not take key status, so they
  are unaffected (*spike 0e* confirms this).
- There is no activation fallback in v1. If the spike fails for some apps, we add one then.

### 2.3 Text editor: `LargeTextView: NSTextView` in `NSScrollView`
- Font size: default 64 pt, range 24–200 pt, step 8 pt (`FontSizePolicy`). High contrast.
- Plain text (`isRichText = false`) with `allowsUndo = true`. Smart quotes and dashes, automatic text
  replacement, spelling correction, continuous spell checking and automatic text completion are **all
  off**, because the main targets are URL bars and search boxes.
- When the overlay opens with initial text (a selection or a draft), that text starts **fully selected**,
  like a URL bar: typing replaces it.
- **Key handling:** `LargeTextView` overrides `keyDown(with:)` and `performKeyEquivalent(with:)`:
  1. If `hasMarkedText()` is true (IME composition in progress), call `super`. ↩ and ⎋ belong to the input
     method.
  2. Otherwise build a `KeyInput` (`keyCode`, `charactersIgnoringModifiers`, modifiers). The pure
     `EditorKeyBindings.action(for:)` returns an `EditorAction?`.
  3. If the result is `nil`, call `super`. That is normal typing.

  | Key | `EditorAction` | Effect |
  |---|---|---|
  | ↩ | `.commit(.insert)` | intent `.commit` |
  | ⌘↩ | `.commit(.insertAndSubmit)` | intent `.commit` |
  | ⇧↩ / ⌥↩ | `.newline` | `insertNewlineIgnoringFieldEditor` locally |
  | ⎋ | `.cancel` | intent `.cancel(.userCancelled)` |
  | ⌘= / ⌘+ (⌘⇧=) / ⌘- / ⌘0 | `.zoom(step)` | intent `.zoom` |
  | ⌘Z / ⌘⇧Z | `.standardEdit(.undo / .redo)` | `undoManager?.undo()` / `redo()`, guarded by `canUndo` / `canRedo` |
  | ⌘X / ⌘C / ⌘V / ⌘A | `.standardEdit(…)` | direct calls on the text view: `cut(nil)`, `copy(nil)`, `paste(nil)`, `selectAll(nil)` |
  | global hotkey (handled by Kit) | — | `coordinator.toggle()` → the normal commit path (§3.5) |

  Zoom keys are matched by the character first, then by key code, so they work across keyboard layouts.
  Standard edits are **direct method calls on the text view**, not responder-chain `sendAction`. That
  doesn't depend on `NSApp.keyWindow` while the app is inactive. **The package never installs or changes
  `NSApp.mainMenu`**, which is the host app's business. `performKeyEquivalent` returns `false` unless
  `window?.firstResponder === self`, because AppKit calls it on every view in the window.
- **Undo is reset per session:** `undoManager?.removeAllActions()` in `present`, because the panel is reused.
- **Committing mid-composition:** `dismiss()` calls `inputContext?.discardMarkedText()` before reading the
  text.

### 2.4 Capturing the target
Done at hotkey time, *before* the overlay is shown. The latency target is about 150 ms; it is measured and
logged, not enforced.
1. `NSWorkspace.shared.frontmostApplication` gives pid, bundle id and name. If the frontmost app is
   **LargeText itself**, AX is skipped, because AX calls into our own main thread block until timeout.
2. Once at startup: `AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.1)`.
3. `AXUIElementCreateApplication(pid)`, then read `kAXFocusedUIElementAttribute`. Read
   `kAXFocusedWindowAttribute` too, as a frame fallback.
4. One batched `AXUIElementCopyMultipleAttributeValues` read gets role, subrole, selected text, position and
   size. A failed attribute comes back as an `AXValue` of type `kAXValueAXErrorType`. The pure helper
   `AXBatchResult` unwraps each attribute to `nil` and is unit-tested.
5. Frame conversion: AX uses top-left-origin global coordinates. Flip them against the **primary screen**
   (`NSScreen.screens.first`, the one with origin 0,0), not `NSScreen.main`. Use the element frame, or
   the focused window frame if that is missing.
6. *Spike 0j:* setting `AXManualAccessibility = true` on Electron app elements, so focus and selection can be
   read. Do **not** set `AXEnhancedUserInterface`; it breaks Chrome's window animations.

**Classification** (pure `static func ElementKind.classify(role:subrole:) -> ElementKind?`, unit-tested):
- `elementKind == nil` means *unknown*, and **we still paste**. Unknown covers three cases:
  - there is no permission;
  - Chromium returned nothing (the common Chrome-omnibox case);
  - the role is ambiguous, e.g. `AXGroup` or `AXWebArea`. Contenteditable editors such as Gmail compose,
    Slack and Notion report these roles.
- `.notEditable` applies only to an **explicit list** of roles that are definitely not text: button, list,
  outline, table, image, menu and menu item, toolbar, scroll bar, slider. Copy only.
- `.secureText` means refuse.

**Prefill:** the selected text, if any. Pasting replaces the selection, so "edit selection → commit"
replaces exactly what was selected. With no selection, a commit inserts at the caret. Prefilling with the
whole field value would need ⌘A before pasting, so it is deferred.

**Secure fields:** we refuse with the notice *"Password fields aren't supported"*. Showing a password at
64 pt to the whole room, and putting it on the clipboard, works against the field's purpose. This is a PRD
question.

### 2.5 Inserting text

**Route (`InsertionRoute.decide(target:permissions:)`).** A pure function and the single source of truth.
The coordinator calls it to choose the header hints when the overlay opens, and the inserter calls it again
at commit time.

| Condition | Route |
|---|---|
| event posting not permitted | `.copyOnly(.permissionMissing)` |
| `target.application == nil` (LargeText was frontmost) | `.copyOnly(.noEditableTarget)` |
| `elementKind == .notEditable` | `.copyOnly(.noEditableTarget)` |
| otherwise (including an unknown element) | `.paste` |

**`PasteboardTextInserter`** is the only live `TextInserting`. Its logic lives in Core; Platform supplies thin
primitives. Every copy-only exit goes through one helper, `ClipboardWriter.copy(text, reason:) ->
InsertionOutcome`. That helper writes **non-transient**, current-host-only text: the user is expected to
paste it by hand, so clipboard-manager history is fine here.

1. **Route.** `.copyOnly(reason)` → `ClipboardWriter`, done.
2. **Focus-return guard.** Wait `timing.focusReturnDelay` (default from spike 0a). Then compare
   `focus.keyboardFocusProcessIdentifier` with `target.pid`. When AX is trusted, that value is the system-wide
   `kAXFocusedApplicationAttribute`, which shows whether keyboard focus actually came back; otherwise it is
   the frontmost pid. On a mismatch, copy only with `.targetChanged`. A focused-*element* mismatch is only
   logged, because web content hands out fresh AX wrappers.
3. **Wait for modifiers to be released.** Poll `keystrokes.pressedModifiers` (HID state) every
   `pollInterval`, up to `maxModifierPolls` times. The limit is a poll *count*, so tests with an instant
   sleeper cannot hang. If keys are still held, copy only with `.modifiersHeld`. ⌘V is never posted then:
   a held ⌘ would turn the submit ↩ into ⌘↩, which opens a new browser tab. This step runs *before* the
   snapshot, so a failed wait never costs a pasteboard read.
4. **Text is pasted verbatim** *(revision 5: the newline-flattening policy below was removed; whitespace
   and line breaks are never altered, and the target decides how to handle them)*. ~~`InsertionTextPolicy.prepare(text, for: target)` replaces newlines with spaces when
   `InsertionTextPolicy.flattensNewlines(for: target)` is true.~~ That is the case for single-line roles
   (`AXTextField`, `AXSearchField`, `AXComboBox`) and for known terminal bundle ids (Terminal, iTerm2,
   Ghostty, Warp, …). Pasting multi-line text into a shell can execute commands.
5. **Snapshot** the general pasteboard according to `preferences.clipboardRestore`:
   - `.restore(maxBytes: 10 MB)` (default). Skips `dyn.*` and file-promise types. Over budget → the snapshot
     is marked incomplete and the restore is lossy.
   - `.none`. No snapshot and no restore, so the outcome is `.inserted(clipboardOverwritten: true)` and the
     HUD says "Your clipboard now contains this text". This is the escape hatch for the macOS 15.4+
     pasteboard privacy prompts. Set it with `defaults write <bundle id> LargeText.clipboardRestore none`;
     v1 has no settings UI.
6. **Write** our string. Call `clearContents()`, then `prepareForNewContents(with: .currentHostOnly)`, then
   add the `org.nspasteboard.TransientType` and `org.nspasteboard.AutoGeneratedType` markers.
7. **Post** ⌘↓ V↓ V↑ ⌘↑ to `.cghidEventTap`, from a `.privateState` event source with explicit flags. The
   key code for "v" comes from the **ASCII-capable** layout
   (`TISCopyCurrentASCIICapableKeyboardLayoutInputSource` + `UCKeyTranslate` with ⌘ state), falling back to
   `kVK_ANSI_V`.
8. **Submit** (optional): post ↩.
9. **Return the outcome**, then **restore in a tail task**: after `restoreDelay` (600 ms), restore the
   snapshot only if `changeCount` still equals the value we produced. A new commit in the meantime changes
   `changeCount`, so the stale restore is skipped safely. The task is kept in `pendingRestore` (package),
   so tests can `await` it.

Strategies for later, behind the same protocol:
- set AX `kAXSelectedTextAttribute`, then read it back to verify;
- type the text as `CGEvent` unicode keystrokes;
- press the target's *Edit › Paste* menu item via AX.

### 2.6 Permissions
- There are two checks: `AXIsProcessTrusted()` (reading focus) and `CGPreflightPostEventAccess()` (posting).
  Insertion is gated on the second, because `CGEvent.post` fails silently.
- **First launch:** if access isn't granted, call `requestAccessibility()` once. That shows the system
  prompt, outside any session.
- **Status menu:** shows "Accessibility: Granted ✓" or "Grant Access…". The second opens
  `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`. The status is re-read in
  `menuNeedsUpdate(_:)`. There is no separate permission window in v1.
- *Spike 0i:* does posting work right after granting, without a relaunch? If not, the menu item becomes
  "Relaunch to finish setup".
- `IsSecureEventInputEnabled()` is logged as a diagnostic only. It is never a gate, because stale holders
  are common.

### 2.7 App shell
- Accessory app: `LSUIElement = YES` in the host's Info.plist, plus `NSApp.setActivationPolicy(.accessory)`
  defensively.
- `NSStatusItem` menu with these items:
  - *Open Large Editor (⌃⌥⌘T)*
  - the permission item
  - the shortcut error, if any
  - *Quit*
- The host app has no storyboard (§3.9).

---

## 3. Architecture

### 3.1 Principles
- **One coordinator owns the session.** Views emit *intents*; the coordinator decides and pushes *chrome*
  (everything except the text) back. **Exception, by design:** the text view owns the text being edited.
  The coordinator gets the text exactly once, from `dismiss()`. Round-tripping keystrokes through the
  coordinator would destroy the caret, the undo stack and IME state.
- **Every side effect sits behind a protocol (a "port").** Live adapters are in Platform and UI. Simple fakes
  are in Core `Fakes/`. Spies and recorders are in TestSupport.
- **Single composition root.** Kit assembles everything from one `AppEnvironment` value. A scenario is a
  mutation of that value, applied before assembly.
- **Initializers have no side effects.** No observers, prompts, Carbon handlers or windows in `init`; they come
  in `start()` or on first use. That makes it free to construct a full live environment and then replace
  parts of it.
- **Pure core.** Domain logic imports Foundation, plus `os` for logging.
- **Swift 6, main-actor by design.**
  - Reference types (ports, coordinator, adapters) are explicitly `@MainActor`.
  - Plain value models are explicitly `Sendable`. The exceptions are `FocusTarget` and `ElementHandle`,
    which wrap an AX object and never leave the main actor.
  - No `@unchecked Sendable` anywhere.
- **Testable async.** The coordinator's entry points are `async`. Live callbacks wrap them in
  `Task { await … }`, and tests `await` them directly. No `AsyncStream`.
- **Access control:**
  - Cross-module API is `package`.
  - The public surface is two types: `LargeTextApplication` (only `run(launch:)`) and
    `LaunchConfiguration` (only `current`).
  - No `public` declaration exposes a `package` type.
- **No third-party dependencies** in v1.

### 3.2 Package layout & module graph

```
LargeText/
├── Package.swift
├── Sources/
│   ├── LargeTextCore/         Models, ports, coordinator, InsertionRoute, policies, inserter, Fakes/. Foundation only.
│   ├── LargeTextPlatform/     Live adapters: Carbon, AX, NSPasteboard, CGEvent, TIS, UserDefaults, NSWorkspace.
│   ├── LargeTextUI/           AppKit: overlay panel & editor, HUD, status item, #Previews.
│   └── LargeTextKit/          AppEnvironment, Scenario, AppController, LargeTextApplication, LaunchConfiguration.
└── Tests/
    ├── LargeTextTestSupport/  Spies & recorders + EventLog (regular target, test-only consumers, never shipped).
    ├── LargeTextCoreTests/
    ├── LargeTextPlatformTests/
    ├── LargeTextUITests/
    └── LargeTextKitTests/
```

```
                 ┌────────────────┐
                 │  LargeTextKit  │  composition root · public facade · scenarios
                 └──┬──────────┬──┘
           ┌────────▼──┐    ┌──▼───────┐
           │ Platform  │    │    UI    │      (never import each other)
           └────────┬──┘    └──┬───────┘
                 ┌──▼──────────▼──┐
                 │      Core      │  ◀── TestSupport ◀── *Tests
                 └────────────────┘
```

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LargeText",
    platforms: [.macOS(.v14)],
    products: [.library(name: "LargeTextKit", targets: ["LargeTextKit"])],
    targets: [
        .target(name: "LargeTextCore"),
        .target(name: "LargeTextPlatform", dependencies: ["LargeTextCore"]),
        .target(name: "LargeTextUI", dependencies: ["LargeTextCore"]),
        .target(name: "LargeTextKit", dependencies: ["LargeTextCore", "LargeTextPlatform", "LargeTextUI"]),
        .target(name: "LargeTextTestSupport", dependencies: ["LargeTextCore"],
                path: "Tests/LargeTextTestSupport"),          // plain library; must not import Testing
        .testTarget(name: "LargeTextCoreTests", dependencies: ["LargeTextCore", "LargeTextTestSupport"]),
        .testTarget(name: "LargeTextPlatformTests", dependencies: ["LargeTextPlatform"]),
        .testTarget(name: "LargeTextUITests", dependencies: ["LargeTextUI"]),
        .testTarget(name: "LargeTextKitTests", dependencies: ["LargeTextKit", "LargeTextCore", "LargeTextTestSupport"]),
    ]
)
```
Scenarios are **compiled unconditionally**: four small enum cases that only run when `--scenario` is passed.
That keeps `#if` out of the code and gives Kit tests and Release builds the same view of the code. A user
*could* pass `--scenario` to a Release build. That is harmless: it only swaps in fakes.

Toolchain: Swift Testing needs the Xcode 16+ toolchain. The plain Command Line Tools may lack `Testing`.

### 3.3 Core models (`LargeTextCore`)

All are `package`; bodies are abbreviated. Everything is `Sendable` except `FocusTarget` and `ElementHandle`.

```swift
// ── Input ──────────────────────────────────────────────────────────────
struct Modifiers: OptionSet, Hashable, Codable, Sendable { command, option, control, shift }
struct KeyCombo: Hashable, Codable, Sendable { var keyCode: UInt32; var modifiers: Modifiers }   // Carbon key code
enum HotkeyError: Error, Equatable, Sendable { case unavailable(KeyCombo) }
enum Keystroke: Equatable, Sendable { case paste, returnKey }

// ── Target ─────────────────────────────────────────────────────────────
struct TargetApplication: Equatable, Sendable { let processIdentifier: Int32; let bundleIdentifier: String?; let localizedName: String }
enum ElementKind: Equatable, Sendable { case singleLineText, multiLineText, secureText, notEditable }
struct ElementHandle { let raw: AnyObject }                  // AXUIElement in production; logging only in v1
struct FocusTarget {
    let application: TargetApplication?   // nil when LargeText itself was frontmost
    let element: ElementHandle?
    let elementKind: ElementKind?         // nil = unknown → still paste
    let selectedText: String?
    let frame: CGRect?                    // element ?? focused window; AppKit global coordinates
}

// ── Session ────────────────────────────────────────────────────────────
struct EditingSession: Identifiable { let id: UUID; let target: FocusTarget }
enum CommitMode: Equatable, Sendable { case insert, insertAndSubmit }
enum CancelReason: Equatable, Sendable { case userCancelled, lostFocus }        // logged

// ── Insertion ──────────────────────────────────────────────────────────
enum InsertionFallbackReason: Equatable, Sendable { case permissionMissing, noEditableTarget, targetChanged, modifiersHeld }
enum InsertionRoute: Equatable, Sendable {
    case paste, copyOnly(InsertionFallbackReason)
    static func decide(target: FocusTarget, permissions: Permissions) -> InsertionRoute   // §2.5 table
}
enum InsertionOutcome: Equatable, Sendable {
    case inserted(clipboardOverwritten: Bool)                 // true when ClipboardRestorePolicy.none
    case copiedToClipboard(InsertionFallbackReason)
}
enum ClipboardRestorePolicy: Equatable, Codable, Sendable { case restore(maxBytes: Int), none }
struct InsertionTiming: Equatable, Sendable {
    var focusReturnDelay: Duration        // default from spike 0a (start: 50 ms)
    var pollInterval: Duration            // 20 ms
    var maxModifierPolls: Int             // 15 (≈300 ms)
    var restoreDelay: Duration            // 600 ms
    static let `default`: InsertionTiming
}
struct PasteboardSnapshot: Equatable, Sendable {
    struct Item: Equatable, Sendable { var dataByType: [String: Data] }
    var items: [Item]
    var isComplete: Bool
}

// ── Presentation ───────────────────────────────────────────────────────
struct FontSize: Equatable, Codable, Sendable { let points: Double }
enum ZoomStep: Equatable, Sendable { case bigger, smaller, reset }
enum FontSizePolicy {                                         // default 64, range 24…200, step 8
    static let `default`: FontSize
    static func apply(_ step: ZoomStep, to size: FontSize) -> FontSize
}
struct TargetHints: Equatable, Sendable {
    var willCopyToClipboard: Bool         // InsertionRoute.decide(...) is .copyOnly
}
struct OverlayChrome: Equatable, Sendable {                   // everything the overlay draws except the text
    var fontSize: FontSize
    var targetName: String?               // "Typing into Safari"
    var targetBundleIdentifier: String?   // UI resolves the icon; Core never sees NSImage
    var targetFrame: CGRect?              // UI picks the screen
    var hints: TargetHints
}
struct OverlayIntent: Equatable, Sendable {                   // tagged with its session; stale ones are ignored
    let sessionID: UUID
    let kind: Kind
    enum Kind: Equatable, Sendable {
        case commit(CommitMode)
        case cancel(CancelReason)         // ⎋, backdrop click (.userCancelled); resign key (.lostFocus)
        case zoom(ZoomStep)
    }
}
enum Notice: Equatable, Sendable {
    case copiedToClipboard(InsertionFallbackReason)
    case clipboardReplaced                // inserted with ClipboardRestorePolicy.none
    case secureFieldUnsupported
    case hotkeyUnavailable(KeyCombo)
}

// ── Permissions ────────────────────────────────────────────────────────
enum PermissionStatus: Equatable, Sendable { case granted, denied }
struct Permissions: Equatable, Sendable { var accessibility: PermissionStatus; var eventPosting: PermissionStatus }
```

### 3.4 Ports (protocols) in Core

```swift
@MainActor protocol HotkeyRegistering: AnyObject {
    func register(_ combo: KeyCombo, handler: @escaping @MainActor () -> Void) throws(HotkeyError) -> any HotkeyRegistration
}
@MainActor protocol HotkeyRegistration: AnyObject { func unregister() }

@MainActor protocol FocusCapturing: AnyObject {
    func captureFocus() -> FocusTarget
    /// System-wide kAXFocusedApplicationAttribute pid when AX is trusted, else the frontmost app's pid.
    var keyboardFocusProcessIdentifier: Int32? { get }
}

@MainActor protocol PermissionsProviding: AnyObject {
    var current: Permissions { get }                         // always a fresh read
    func requestAccessibility()                              // system prompt
    func openSystemSettings()
}

@MainActor protocol PasteboardClient: AnyObject {
    var changeCount: Int { get }
    func snapshot(maxBytes: Int) -> PasteboardSnapshot
    func restore(_ snapshot: PasteboardSnapshot)
    /// Clears, sets .currentHostOnly, writes; `transient` adds the nspasteboard.org markers. Returns the new changeCount.
    @discardableResult func write(_ string: String, transient: Bool) -> Int
}

@MainActor protocol KeystrokeSending: AnyObject {
    var pressedModifiers: Modifiers { get }                  // physical (HID) state
    func send(_ stroke: Keystroke)
}

@MainActor protocol TextInserting: AnyObject {
    func insert(_ text: String, into target: FocusTarget, mode: CommitMode) async -> InsertionOutcome
}

@MainActor protocol PreferencesStore: AnyObject {            // class-bound: one shared instance
    var fontSize: FontSize { get set }
    var hotkey: KeyCombo { get set }
    var clipboardRestore: ClipboardRestorePolicy { get set }
}

protocol Sleeper: Sendable { func sleep(for duration: Duration) async throws }

@MainActor protocol OverlayPresenting: AnyObject {
    /// Resets undo; `initialText` is applied once and fully selected if non-empty. Afterwards the view owns the text.
    func present(sessionID: UUID, initialText: String, chrome: OverlayChrome,
                 intents: @escaping @MainActor (OverlayIntent) -> Void)
    func update(_ chrome: OverlayChrome)                     // never touches the text
    /// Stops emitting intents immediately, discards marked text, orders out (fade),
    /// and returns the text. This is the ONLY way the coordinator obtains the text.
    func dismiss() async -> String
}

@MainActor protocol NoticePresenting: AnyObject { func show(_ notice: Notice) }
```

### 3.5 The coordinator: `EditingSessionCoordinator` (Core)

```swift
@MainActor
final class EditingSessionCoordinator {
    enum Phase: Equatable, Sendable { case idle, editing(sessionID: UUID), closing(sessionID: UUID) }

    private(set) var phase: Phase = .idle
    private var session: EditingSession?
    private var draft: String?                                // last cancelled text, in memory only

    init(dependencies: CoreDependencies)
    func toggle() async                                       // hotkey & menu & present-on-launch
    func handle(_ intent: OverlayIntent) async                // from the overlay
}

struct CoreDependencies {
    var focus: any FocusCapturing
    var permissions: any PermissionsProviding                 // for TargetHints (InsertionRoute)
    var inserter: any TextInserting
    var overlay: any OverlayPresenting
    var notices: any NoticePresenting
    var preferences: any PreferencesStore
}
```

Live wiring:
- Kit's hotkey handler calls `Task { await coordinator.toggle() }`.
- The coordinator itself builds the `intents` closure it passes to `present(...)`:
  `{ [weak self] intent in Task { await self?.handle(intent) } }`.
- Each entry point sets `phase` **synchronously, before its first `await`**. Main-actor tasks run in order,
  so a second task queued behind the first always sees `closing`.
- Tests call `handle(_:)` directly and never invoke the closure captured by `SpyOverlay`.

`closing` ends as soon as `insert` returns, which happens right after the keystrokes are posted. The
600 ms clipboard restore runs afterwards as a tail task (§3.6), so the hotkey is responsive again
immediately.

**Transition table.** Each row is a unit test.

| Phase | Event | Effect → next phase |
|---|---|---|
| idle | `toggle()`, target `.secureText` | notice `.secureFieldUnsupported` → idle (overlay never shown) |
| idle | `toggle()` | capture focus; initial text = selection ?? draft ?? ""; hints from `InsertionRoute` and `InsertionTextPolicy` → present → **editing** |
| editing | `toggle()` | same as `.commit(.insert)` |
| editing | `.commit(mode)` | **closing** → `text = await dismiss()` → if empty → **idle** (draft untouched); else `await inserter.insert` → notice for `.copiedToClipboard` / `clipboardOverwritten` → draft = nil → **idle** |
| editing | `.cancel(reason)` | **closing** → `text = await dismiss()` → draft = text if non-empty → **idle** |
| editing | `.zoom(step)` | `FontSizePolicy.apply` → persist → `overlay.update(chrome)` |
| closing | `toggle()` or any intent | ignored |
| any | intent with a stale `sessionID` | ignored |

The draft always opens fully selected. A draft from Safari reopened over Slack is replaced by the first
keystroke, so it is never pasted by accident. The router re-reads permissions at commit time, so a
mid-session permission change needs no extra handling.

### 3.6 Insertion (Core)

```swift
@MainActor final class PasteboardTextInserter: TextInserting {          // the only live TextInserting
    init(permissions: any PermissionsProviding, pasteboard: any PasteboardClient,
         keystrokes: any KeystrokeSending, focus: any FocusCapturing,
         preferences: any PreferencesStore, sleeper: any Sleeper, timing: InsertionTiming = .default)
}
@MainActor struct ClipboardWriter {                                     // shared copy-only exit
    let pasteboard: any PasteboardClient
    func copy(_ text: String, reason: InsertionFallbackReason) -> InsertionOutcome   // non-transient write
}
enum InsertionTextPolicy {
    static func flattensNewlines(for target: FocusTarget) -> Bool
    static func prepare(_ text: String, for target: FocusTarget) -> String
}
```

The steps in §2.5 (route → guard → modifier polls → policy → snapshot → write → ⌘V → ↩ → return →
conditional restore in `pendingRestore: Task<Void, Never>?`) are tested in Core against TestSupport spies. The modifier wait is bounded by a poll count, so
tests cannot hang.

**Core `Fakes/`** are tiny and Foundation-only, used by scenarios, the vertical slice and tests:
`StubFocusCapturer`, `FixedPermissions`, `LoggingTextInserter`, `LoggingNoticePresenter`,
`InMemoryPreferencesStore`, `InstantSleeper`.

**TestSupport** (tests only):
- `EventLog`: one shared, ordered array of `RecordedEvent`. Every spy appends to it, so a test can assert
  ordering across ports, e.g. `[.dismiss, .snapshot, .write, .key(.paste), .key(.returnKey), .restore, .notice(…)]`.
- `SpyOverlay`: records present, update and dismiss. `dismiss()` can be held open on a test-controlled
  continuation (`holdDismiss = true`, then `completeDismiss(returning:)`). That is how a test sends a late
  `.cancel(.lostFocus)` or `toggle()` while the coordinator is in `closing`.
- `SpyNotices`, `FakePasteboard`, `RecordingKeystrokes` (a scripted `pressedModifiers` sequence),
  `SpyInserter`, `RecordingSleeper`.

### 3.7 Live adapters (`LargeTextPlatform`)

| Type | Implements | Notes |
|---|---|---|
| `CarbonHotkeyRegistrar` | `HotkeyRegistering` | Installs one `InstallEventHandler` lazily. The C callback gets `Unmanaged` self, then `MainActor.assumeIsolated` (Carbon dispatches on main). |
| `AccessibilityFocusCapturer` | `FocusCapturing` | §2.4. Pure, unit-tested helpers: `AXGeometry.appKitRect(axPosition:axSize:primaryScreenFrame:)`, `ElementKind.classify(role:subrole:) -> ElementKind?` (explicit not-text list; `nil` = unknown), `AXBatchResult`. |
| `SystemPermissionsProvider` | `PermissionsProviding` | `AXIsProcessTrusted`, `CGPreflightPostEventAccess`, `AXIsProcessTrustedWithOptions`. |
| `SystemPasteboardClient` | `PasteboardClient` | Takes an `NSPasteboard` in `init` (`.general` live, a named board in tests). Pure `SnapshotTypeFilter`. |
| `CGEventKeystrokeSender` | `KeystrokeSending` | `KeyboardLayoutResolver` (ASCII-capable layout) and a `.privateState` source. |
| `UserDefaultsPreferencesStore` | `PreferencesStore` | Keys use the `LargeText.` prefix (`fontSize`, `hotkey`, `clipboardRestore`). |
| `TaskSleeper` | `Sleeper` | `Task.sleep(for:)`. |

### 3.8 UI (`LargeTextUI`)

| Type | Role |
|---|---|
| `OverlayPanel: NSPanel` | Non-activating (set in `init`), borderless, can become key, `.fullScreenAuxiliary`, level `.statusBar + 1`. |
| `OverlayWindowController` | Implements `OverlayPresenting`. Picks the screen with `ScreenResolver`. Backdrop covers `screen.frame`. Fades for at most 120 ms and respects *Reduce Motion*. Applies the resign-key rule. Suppresses intents from the start of `dismiss()`. |
| `EditorViewController` | Backdrop, card, header (icon, "Typing into Safari", hints), `LargeTextView`, footer hints. Renders `OverlayChrome`. Maps `EditorAction` to intents or local actions. |
| `LargeTextView: NSTextView` | Key interception (§2.3; first-responder guard in `performKeyEquivalent`), marked-text handling, direct standard edits. |
| `EditorKeyBindings` | Pure function `(KeyInput) -> EditorAction?`. `KeyInput { keyCode, charactersIgnoringModifiers, modifiers }`. `EditorAction { commit(CommitMode), cancel, newline, zoom(ZoomStep), standardEdit(StandardEdit) }`. `StandardEdit { undo, redo, cut, copy, paste, selectAll }`. |
| `ScreenResolver` | Pure function `(targetFrame?, mouseLocation, [ScreenDescriptor]) -> ScreenDescriptor`, where `ScreenDescriptor { id, frame, visibleFrame }`. Order: target frame, then the screen under the mouse, then the primary screen. |
| `HUDNoticePresenter` | Implements `NoticePresenting`. A non-key `NSPanel` with the overlay's level and `collectionBehavior` and large text. Auto-hides after 2.5 s. |
| `StatusItemController` | The menu from §2.7. Re-reads permissions in `menuNeedsUpdate`. Driven by Kit. |
| `Theme` | All colors and metrics in one place. |
| `#Preview`s | `EditorViewController` in these states: empty, prefilled, long text, flattens-newlines hint, will-copy hint. The fast visual loop (macOS 14; select the package scheme in Xcode). |

Overlay visuals (v1, deliberately simple, tuned after hands-on):
- Backdrop: black at 55% opacity.
- Card: about 80% of the screen width, `NSVisualEffectView` with `.hudWindow`, corner radius 24.
- Header: icon plus target name, at 0.4× the editor font size.
- Editor: grows up to 60% of the screen height, then scrolls.
- Footer: `↩ Insert   ⌘↩ Insert & Submit   ⎋ Cancel   ⌘± Size`, at 0.3× the editor font size.

### 3.9 Composition root, running in a given state, host app (`LargeTextKit`)

```swift
package struct AppEnvironment {                    // plain instances; constructing them has no side effects
    package var hotkeys: any HotkeyRegistering
    package var focus: any FocusCapturing
    package var permissions: any PermissionsProviding
    package var pasteboard: any PasteboardClient
    package var keystrokes: any KeystrokeSending
    package var preferences: any PreferencesStore
    package var sleeper: any Sleeper
    package var overlay: any OverlayPresenting
    package var notices: any NoticePresenting
    package var inserterOverride: (any TextInserting)?   // nil → PasteboardTextInserter built from the services above

    @MainActor package static func live() -> AppEnvironment
    /// Assembly runs AFTER scenario mutation, so overrides are always respected.
    @MainActor package func coreDependencies() -> CoreDependencies
}

package enum Scenario: String, CaseIterable, Sendable {
    case overlayPrefilled  = "overlay-prefilled"   // StubFocusCapturer(Safari, selection "https://www.apple.com"),
                                                   // LoggingTextInserter. Use with --present-on-launch.
    case noEditableTarget  = "no-editable-target"  // StubFocusCapturer(.notEditable); real clipboard → HUD
    case permissionMissing = "permission-missing"  // FixedPermissions(.denied); real inserter → copy-only HUD
    case loggingInsertion  = "logging-insertion"   // everything live except LoggingTextInserter
    // Note: with inserterOverride set, header hints still reflect the real InsertionRoute (expected).

    @MainActor package func apply(to env: inout AppEnvironment)   // also swaps in InMemoryPreferencesStore
}

public struct LaunchConfiguration: Equatable, Sendable {
    package var scenario: Scenario?                // `--scenario <name>`; unknown names are logged and ignored
    package var presentOnLaunch: Bool              // `--present-on-launch` → coordinator.toggle() after start
    public static var current: LaunchConfiguration { .init(arguments: ProcessInfo.processInfo.arguments) }
    package init(arguments: [String])              // pure, unit-tested
}

@MainActor
public enum LargeTextApplication {
    /// Builds env (live → scenario), creates the AppController, keeps it alive, sets it as the
    /// delegate, runs NSApplication, then exit(0).
    public static func run(launch: LaunchConfiguration = .current) -> Never
    private static var controller: AppController?  // NSApplication.delegate is weak
}

@MainActor
package final class AppController: NSObject, NSApplicationDelegate {
    package init(environment: AppEnvironment, launch: LaunchConfiguration)   // stores only; no side effects
    // applicationDidFinishLaunching → start(); applicationWillTerminate → stop()
}
```

**Kit-owned responsibilities.** These are not ports, and scenarios do not control them.

`AppController.start()`, in order:
1. Set the activation policy.
2. Build the coordinator from `environment.coreDependencies()`.
3. Create the status item.
4. Register the hotkey: handler → `Task { await coordinator.toggle() }`. On `HotkeyError`, show a notice
   and a menu item.
5. Call `requestAccessibility()` once if access is missing.
6. If `presentOnLaunch`: `Task { await coordinator.toggle() }`.

`stop()` unregisters the hotkey and removes the status item.

Every scenario documents what stays live. For example, `permission-missing` keeps the real pasteboard, so you
see the actual copy-only behaviour. Purely visual states are covered by `#Preview`s, not scenarios.

**Host Xcode app.** Create a macOS App (AppKit) target, then:
1. Delete `AppDelegate.swift`, `Main.storyboard` and the `NSMainStoryboardFile` Info.plist key.
2. Set `LSUIElement = YES`, remove the App Sandbox capability, keep Hardened Runtime.
3. Sign with your development team (see §6).
4. Add `main.swift`:

```swift
import LargeTextKit
LargeTextApplication.run()
```

`@main` on an `NSApplicationDelegate` only works if a nib or storyboard connects the delegate, so we use
explicit `main.swift` instead. Top-level code in `main.swift` runs on the main actor.

For scenario schemes in Xcode, set *Arguments Passed On Launch* to
`--scenario overlay-prefilled --present-on-launch`.

### 3.10 Data flow: one complete commit

```
User ⌃⌥⌘T
  └─▶ CarbonHotkeyRegistrar ─(Kit)─▶ Task { await coordinator.toggle() }
        ├─ focus.captureFocus()   → FocusTarget{Safari, .singleLineText, selection:"apple.com", frame}
        ├─ hints = {willCopy: route != .paste, flattensNewlines: true}
        ├─ phase = .editing(id)
        └─ overlay.present(id, "apple.com" (selected), chrome{64pt, "Safari", hints}, intents)
User types (text lives in LargeTextView), presses ⌘+
  └─▶ EditorKeyBindings → .zoom(.bigger) → intent ─▶ coordinator → prefs.fontSize = 72 → overlay.update
User presses ⌘↩
  └─▶ intent(id, .commit(.insertAndSubmit)) ─▶ Task { await coordinator.handle(intent) }
        ├─ phase = .closing(id)                   (synchronously, before any await)
        ├─ text = await overlay.dismiss()         (intents suppressed, marked text discarded, fade out)
        ├─ await inserter.insert(text, target, .insertAndSubmit)
        │     route .paste → focusReturnDelay → focused-app pid guard → modifier polls →
        │     flatten newlines → snapshot → write (transient, current host) → ⌘↓V↓V↑⌘↑ → ↩ →
        │     return outcome   (tail task: sleep 600 ms → restore if changeCount unchanged)
        ├─ outcome .inserted(clipboardOverwritten: false) → draft = nil
        └─ phase = .idle          (hotkey responsive again while the restore tail runs)
```

---

## 4. Testing strategy

- **Swift Testing** (`import Testing`) with the Xcode 16+ toolchain.
- **Core coordinator:** every row of the §3.5 table, using `SpyOverlay` with a held `dismiss()`. This
  covers a late `.cancel(.lostFocus)` or `toggle()` during `closing`, stale ids, blank commits, and draft
  prefill and selection. Cross-port ordering is asserted on the shared `EventLog`.
- **Core routing:** for every row of the §2.5 route table, `InsertionRoute.decide` and the `TargetHints`
  shown in the overlay agree. This includes an unknown element → paste.
- **`PasteboardTextInserter`:**
  - full step order;
  - focused-app pid mismatch → `.targetChanged`;
  - `.modifiersHeld` after `maxModifierPolls`, with no snapshot taken;
  - conditional restore;
  - `ClipboardRestorePolicy.none` → `clipboardOverwritten`;
  - incomplete snapshot;
  - copy-only writes are non-transient.
- **Policies:** `InsertionTextPolicy` (single-line roles and terminal bundle ids), `FontSizePolicy`.
- **UI (pure):**
  - `EditorKeyBindings`: ↩ vs ⇧↩ vs ⌘↩; zoom via ⌘=, ⌘⇧= and ⌘- on US and German layouts; standard edits;
    Escape.
  - `ScreenResolver`.
- **Platform (pure):**
  - AX geometry flip against a secondary screen with a non-zero origin;
  - `AXBatchResult` error unwrapping;
  - `ElementKind.classify` (`AXGroup` / `AXWebArea` → nil; button → `.notEditable`);
  - `SnapshotTypeFilter`;
  - a pasteboard round trip on `NSPasteboard(name:)`, never `.general`.
- **Kit:**
  - `LaunchConfiguration` parsing, including unknown scenario names.
  - One **behavioural** assembly test: apply `permission-missing` to an environment built from TestSupport
    spies, call `coreDependencies()`, then toggle and commit. Expect a copy-only outcome and a
    `.copiedToClipboard(.permissionMissing)` notice. This catches assembly-order bugs.
- **Manual matrix** (`docs/manual-testing.md`):
  - Safari URL bar, Chrome omnibox, Firefox, TextEdit, Notes;
  - Slack and VS Code (Electron), Gmail compose (contenteditable);
  - Terminal and iTerm (newline flattening);
  - a password field (refusal);
  - full-screen video, two displays;
  - Dvorak and Russian layouts, Japanese IME;
  - ⌘Tab and screen lock during a session;
  - ⌘V inside the editor.
- **Logging:** `os.Logger` lines with durations per session: capture time, focus return time and pid, paste
  time, restore outcome. These numbers feed the PRD.

---

## 5. Milestones

0. **Spike (half a day, throwaway branch).**
   - a) Focus returns to Safari, Chrome and Electron fields after `orderOut`. Measure the delay, whether
     focus returns at the start or the end of the fade, and frontmost pid vs `kAXFocusedApplication` pid.
     The results set `focusReturnDelay`.
   - b) The overlay is visible over a full-screen video Space at `.statusBar + 1`.
   - c) ⌘V via `CGEvent` reaches the Chrome omnibox.
   - e) IME, Dictation and Character Viewer inside the panel. Undo, redo and paste via direct calls in the
     non-activating panel.
   - f) ⌘Tab, Spotlight and screen lock cause resign-key.
   - g) How hotkey registration fails. Whether the hotkey fires under Secure Input, and while our own panel
     is key.
   - h) The pasteboard privacy prompt on the current macOS version. This includes ⌘V *inside the editor*
     during a session: whether the prompt appears under the overlay.
   - i) Permission granted mid-run, with and without a relaunch.
   - j) `AXManualAccessibility` on an Electron app.
1. **Package skeleton.** `Package.swift`; the four library targets plus TestSupport; Core models, ports and
   fakes; `EventLog` and the spies; empty tests passing.
2. **Vertical slice ("feel" starts here).** Built on the final ports and the final coordinator type, it
   includes everything that prevents known misbehaviour:
   - the coordinator rows idle → editing → commit/cancel, with `closing`, intent suppression and stale-id
     checks;
   - the **complete `PasteboardTextInserter`** (guard, modifier wait, snapshot/restore) with
     `ClipboardWriter` for its `.targetChanged` and `.modifiersHeld` exits, and its ordering tests. The router
     only ever produces `.paste`;
   - the real Carbon hotkey, focus capture, overlay panel and editor, and status item;
   - notices through `LoggingNoticePresenter`.

   *You can start using it here.*
3. **Core completion.** Drafts, secure refusal, `InsertionRoute` with the copy-only fallbacks and hints,
   `InsertionTextPolicy`, and the remaining Core tests. *This milestone only adds rows; it does not
   restructure.*
4. **UI polish.** Theme, header and footer, `HUDNoticePresenter`, `#Preview`s, Reduce Motion, multi-display
   screen choice.
5. **Kit completion.** The status-menu permission item, the four scenarios with scheme instructions, the
   behavioural assembly test, and the manual-testing checklist.
6. **Hands-on.** Run the manual matrix and collect opinions for the PRD.

Out of scope for v1:
- hotkey recorder, settings window, theme customization;
- prefill with the whole field, per-app insertion strategies, entry history;
- launch at login (`SMAppService.mainApp`), Sparkle updates;
- an activation fallback, a dedicated permission window;
- a sandboxed Mac App Store build;
- system-event observation (resign-key covers it);
- a host-supplied app delegate (only `run(launch:)` is public).

---

## 6. Risks & mitigations

| Risk | Mitigation |
|---|---|
| ⌘V lands in the wrong app | Resign-key cancels the session. After the focus-return delay, a guard compares the focused-*application* pid (AX) with the target; on mismatch, copy-only. It confirms the app, not the field. The field is assumed to keep first responder, which spike 0a checks. |
| Chrome/Electron/contenteditable expose no or ambiguous element | Unknown is treated as "paste"; `.notEditable` only for an explicit role list; spike `AXManualAccessibility`. |
| Non-activating panel misbehaves in some app | Spike 0a; add an activation port only if needed. |
| Paste race (the target reads late) | 600 ms restore delay, conditional on `changeCount`; `InsertionTiming` is injectable. |
| Pasteboard privacy prompts (macOS 15.4+ `NSPasteboard.accessBehavior` preview; enforcement announced) | Spike 0h; `ClipboardRestorePolicy.none` with a HUD message; modifier wait happens before the snapshot; any related API guarded by `if #available(macOS 15.4, *)`. |
| Snapshot forces lazy or promised data | Type filter and byte budget; lossy restore. |
| Clipboard managers or Universal Clipboard pick up our text | Transient markers on the paste path; `.currentHostOnly` always. |
| Modifiers still held | HID polling bounded by a count → `.modifiersHeld` copy-only; `.privateState` source; full ⌘ down/up sequence. |
| Non-QWERTY / non-Latin layouts | ASCII-capable layout for the key code; zoom bindings matched by character and by key code. |
| Multi-line paste executes commands in a terminal | Accepted (rev 5): text is pasted verbatim; modern terminals use bracketed paste / multi-line paste warnings. |
| Hung target blocks AX | 0.1 s global timeout, batched reads, AX skipped for our own pid. |
| Overlay level above system prompts | We never trigger prompts during a session; spike 0h covers the one the system triggers (⌘V inside the editor). |
| Undo history leaking across sessions | `removeAllActions()` in `present`. |
| Hotkey conflicts or refusals | ⌃⌥⌘T default; failure surfaced as a notice and a menu item. |
| Secure Input false positives | Diagnostic only. |
| **TCC permission resets during development** | Sign Debug builds with your real team (not "Sign to Run Locally"). Never change the bundle id or signing identity between builds, because TCC keys on the designated requirement. After an intentional change, run `tccutil reset Accessibility <bundle id>`. |

---

## 7. Coding conventions

- Swift 6 language mode. Reference types that touch UI, AX, the pasteboard or coordination are explicitly
  `@MainActor`, and value models are explicitly `Sendable`. No ad-hoc `DispatchQueue.main.async`.
- One primary type per file. Feature folders: `Hotkey/`, `Focus/`, `Insertion/`, `Overlay/`, `Permissions/`,
  `Preferences/`, `Fakes/`.
- `package` for cross-module API. The public surface is two types: `LargeTextApplication` (`run(launch:)`)
  and `LaunchConfiguration` (`current`).
- Logging with `os.Logger(subsystem: "LargeText", category: <module>)`.
- Process-wide singletons (`NSPasteboard.general`, `NSWorkspace.shared`, `NSApp`) only in adapters and Kit.
- Typed `enum` errors, with typed `throws` where it helps. User-visible failures always become a `Notice`.

---

## 8. Open questions for the PRD (after hands-on)

- Hotkey choice; whether to add a second "insert & submit" hotkey.
- Overlay style: a full-screen dim or only a floating card; theme; default size.
- Prefill: the selection only, or the whole field.
- Secure fields: keep refusing, or offer a "masked large" mode?
- Clipboard restore: always, never, or configurable (also depends on macOS privacy prompts).
- Newline handling per target: automatic, or the user's choice.
- Draft lifetime and history.
- Distribution: Developer ID only, or the Mac App Store as well?

---

## 9. Revision log

### Round 1 → revision 2
| Finding | Change |
|---|---|
| ⌃⌥Space conflicts with input-source switching | ⌃⌥⌘T default; failure path surfaced. |
| ⌘V could land in the wrong app | Resign-key cancels; pre-insertion guard. |
| The text round-trip broke caret, undo and IME | The view owns the text; `OverlayChrome`; commit carries the text; `discardMarkedText`. |
| `doCommandBy` can't distinguish ↩/⇧↩/⌘↩ | `LargeTextView` key interception with pure bindings. |
| `Phase: Equatable` wouldn't compile; implicit `@MainActor` | Phase uses ids only; explicit `@MainActor` protocols; no `Sendable` models. |
| The sandbox claim was too strong | Reworded. |
| Posting permission ≠ AX trust | Two checks; preflight gating. |
| Pasteboard cost, privacy and sync | Budget, filter, restore policy, `.currentHostOnly`. |
| AX capture could block | Global timeout, app-element query, batched reads, own-pid skip. |
| Coordinate flip | Uses the primary screen. |
| Modifier and layout details | HID polling, full key sequence, ASCII-capable layout. |
| Secure Input flag | Diagnostic only. |
| `.screenSaver` level | `.statusBar + 1`. |
| `PreferencesStore` value-copy bug | Class-bound protocol. |
| Over-modularized; Demo executable | Four library targets; `package` access; Demo removed. |
| Missing transitions; multi-line into shells; late "feel" | Transition table; `InsertionTextPolicy`; vertical slice. |

### Round 2 → revision 3
| Finding | Change |
|---|---|
| §2.4 and §3.6 disagreed on a nil element; Chrome would never paste | One routing table (§2.5): unknown means paste; spike `AXManualAccessibility`. |
| Our own `orderOut` caused resign-key, so cancel ran twice | `closing` entered before any await on every exit path; intents suppressed during dismiss. |
| `@main` AppDelegate without a storyboard never runs; a library installing `mainMenu` clashes with the host | `main.swift` + `LargeTextApplication.run()`; storyboard removed; the package never touches `mainMenu`. |
| Scenarios couldn't replace the inserter, and permission routing read live state | `inserterOverride`; assembly runs after scenario mutation; each scenario documents what stays live. |
| A `@MainActor` struct of plain closures doesn't compile in Swift 6 | Factories replaced with plain side-effect-free instances. |
| Undefined types | All defined in §3.3/§3.8, or removed. |
| Unused or contradictory types (`CancelReason`, `InsertionMethod`, `.permissionNeeded`, `.applicationActivated`) | `CancelReason` now carried by the intent; the others removed. |
| Unclear ownership of hotkey and permission UI | "Kit-owned responsibilities" (§3.9). |
| An `AsyncStream` "multi-subscriber" is single-consumer; extra hops made tests flaky | Synchronous coordinator API; `onPhaseChange`; `SystemEventsObserving` removed (resign-key covers it). |
| An instant sleeper with wall-clock timeouts could hang tests; behaviour when modifiers stay held | Poll count; `.modifiersHeld` copy-only fallback. |
| Character Viewer, our own windows, level vs prompts, `CFEqual` false negatives, AX batch errors | Rules in §2.2, pid-only guard, `AXBatchResult`, 0.1 s timeout, latency target not enforced. |
| Too much scope | 4 scenarios (+ `#Preview`s); no permission window; no signposts; in-memory draft without expiry; no time budget; no hidden menu (deterministic `standardEdit` instead). |
| DI could be simpler | `AppEnvironment` of plain instances plus `inout` scenario mutations; fakes shared from Core `Fakes/`. |
| `DEBUG` is fragile for packages | `LARGETEXT_SCENARIOS` define in `Package.swift`. |
| Vertical slice could become a second architecture | The slice uses the final ports and coordinator; later milestones only add rows. |
| Nice-to-haves | TestSupport `path:`; `package` visibility note; availability notes; `KeyInput` carries characters; text view settings; draft always selected; focused-window frame fallback for screen choice. |

### Round 3 → revision 4
| Finding | Change |
|---|---|
| The coordinator couldn't compute `hint` (no permissions); one hint couldn't show two conditions; terminals had no hint | Pure `InsertionRoute.decide` shared by the coordinator and the inserter; `permissions` in `CoreDependencies`; `TargetHints` struct; `flattensNewlines(for:)`; agreement tests (§2.5, §3.3, §3.5). |
| Two sources of truth for the text; `requestCommit` re-entrancy | Intents carry no text; `requestCommit` removed; `dismiss()` is the only way to get the text; toggle-while-editing = commit (§3.4, §3.5). |
| The async commit path couldn't be awaited in tests | `toggle()` / `handle(_:)` are `async`; live code wraps them in `Task`; `SpyOverlay` with a held dismiss; shared `EventLog` (§3.5, §3.6, §4). |
| Undo/redo via `sendAction(UndoManager.undo)` is wrong; undo history leaked across sessions | Direct calls on the text view; `removeAllActions()` in `present`; `firstResponder` guard (§2.3). |
| Milestone 2 would have shipped the double-cancel and held-modifier bugs | `closing`, suppression, stale ids and the complete pasteboard inserter moved into the slice; `LoggingNoticePresenter` added (§5). |
| Scenario flag didn't reach the Kit tests; wrong rationale | Scenarios compiled unconditionally; flag removed (§3.2). |
| Facade problems: stored static var, unreachable `init(arguments:)`, `run() -> Never` returning, weak delegate, two lifecycles | Computed `current`; `package init(arguments:)`; `run` keeps a static strong reference and calls `exit(0)`; the only public entry is `run(launch:)`; `AppController` owns `start()` / `stop()` (§3.9). |
| `static let` on non-Sendable models doesn't compile | Value models are explicitly `Sendable`; only `FocusTarget` / `ElementHandle` are not (§3.1, §3.3). |
| Copy-only inserter couldn't know the reason; logic duplicated | `ClipboardWriter` helper; one live `TextInserting`; router folded into it (§3.6). |
| `.notEditable` would break contenteditable editors | Explicit not-text role list; `AXGroup` / `AXWebArea` → unknown → paste; Gmail added to the matrix (§2.4). |
| The pid guard was weaker than claimed | Focused-application pid via AX; claim toned down in §6 (§2.5). |
| Reviewer follow-up (agreed: ready to implement) | The coordinator builds the `intents` closure; second-display menu bar wording; `ElementKind.classify` returns an optional; Kit tests depend on Core; `ClipboardWriter` in milestone 2; restore moved to a tail task so `closing` ends at paste; public-surface wording; Release-scenario and hint-drift notes. |
| Nice-to-haves | Resign-key rule simplified; backdrop click defined; backdrop covers the menu bar; `onPhaseChange` dropped; `.clipboardReplaced` notice and `defaults` key; modifier wait before the snapshot; non-transient copy-only writes; `AppAssembly` folded into `AppEnvironment`; explicit `@MainActor` on the inserter; behavioural Kit test; HUD level and spaces behaviour; new spike items. |

### Hands-on feedback → revision 5
| Finding | Change |
|---|---|
| Line breaks were turned into spaces for single-line fields and terminals; many editors support line breaks | `InsertionTextPolicy` and the `flattensNewlines` hint removed. Text is pasted verbatim and the target decides. |
| Whitespace must be respected | Only an *empty* editor counts as "nothing to insert"; whitespace-only text is inserted and kept as a draft. Tests assert leading/trailing whitespace survives editor → dismiss → pasteboard. |
