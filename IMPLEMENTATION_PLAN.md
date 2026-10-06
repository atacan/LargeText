# LargeText — Technical Implementation Plan (v1, revision 3)

> Goal of v1: a working, hands-on prototype of the "large text overlay" idea (see `idea.md`) that is
> **architecturally clean** so it can grow once product opinions form. Delivered as a **Swift package**
> that an Xcode AppKit app target imports and starts with two lines of code.
>
> Revision 3 incorporates two independent review rounds; see §9.

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
- **Resign-key rule:** if the panel loses key status *and the new key window is not ours*, the overlay
  emits `.cancel(reason: .lostFocus)` and the draft is kept. This covers ⌘Tab, Spotlight, clicks on another
  display, screen lock and sleep. Resign-key caused by our own `dismiss()` is suppressed: once a
  programmatic dismiss starts, the controller stops emitting intents.
- Clicking the dimmed backdrop counts as cancel (draft kept).
- The HUD is a separate **non-key** `NSPanel`, so it never steals key status.
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
  | ⌘Z / ⌘⇧Z / ⌘X / ⌘C / ⌘V / ⌘A | `.standardEdit(edit)` | `NSApp.sendAction(selector, to: nil, from: textView)` locally |
  | global hotkey (handled by Kit) | — | coordinator → `overlay.requestCommit(.insert)` |

  Zoom keys are matched by the character first, then by key code, so they work across keyboard layouts.
  The standard editing commands are dispatched deterministically. **The package never installs or changes
  `NSApp.mainMenu`**, which is the host app's business.
- **Committing mid-composition:** before reading the final text, the editor calls
  `inputContext?.discardMarkedText()`.

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

**Classification:**
- `elementKind == nil` (no permission, or Chromium returned nothing) means *unknown*. **We still paste.**
  This is the common Chrome-omnibox case.
- `.notEditable` (a definite non-text role) means copy only.
- `.secureText` means refuse.

**Prefill:** the selected text, if any. Pasting replaces the selection, so "edit selection → commit"
replaces exactly what was selected. With no selection, a commit inserts at the caret. Prefilling with the
whole field value would need ⌘A before pasting, so it is deferred.

**Secure fields:** we refuse with the notice *"Password fields aren't supported"*. Showing a password at
64 pt to the whole room, and putting it on the clipboard, works against the field's purpose. This is a PRD
question.

### 2.5 Inserting text

**Routing (`RoutingTextInserter`, the single source of truth):**

| Condition (checked at commit time) | Result |
|---|---|
| event posting not permitted | copy only, `.permissionMissing` |
| `target.application == nil` (LargeText was frontmost) | copy only, `.noEditableTarget` |
| `elementKind == .notEditable` | copy only, `.noEditableTarget` |
| otherwise (including unknown element) | `PasteboardTextInserter` |

**`PasteboardTextInserter`** (logic in Core, thin primitives in Platform):
1. **Guard.** Wait `timing.focusReturnDelay` (the default is set by spike 0a). If
   `focus.frontmostProcessIdentifier != target.pid`, copy only with `.targetChanged`. A mismatch between the
   focused element and the captured one is only **logged**: web content hands out fresh AX wrappers, so a
   `CFEqual` comparison gives false negatives.
2. **Text policy.** `InsertionTextPolicy.prepare(text, for: target)` replaces newlines with spaces when the
   target is single-line (`AXTextField`, `AXSearchField`, `AXComboBox`) or a known terminal (Terminal,
   iTerm2, Ghostty, Warp, …). Pasting multi-line text into a shell can execute commands.
3. **Snapshot** the general pasteboard according to `ClipboardRestorePolicy`:
   - `.restore(maxBytes: 10 MB)` (default). `dyn.*` and file-promise types are skipped. If the size
     exceeds the budget, the snapshot is marked incomplete and the restore is lossy.
   - `.none`. The clipboard is overwritten and not restored; the HUD can say so. This is the escape hatch
     for the macOS 15.4+ pasteboard privacy prompts.
4. **Write** our string after `clearContents()` and `prepareForNewContents(with: .currentHostOnly)`, so it
   doesn't sync over Universal Clipboard. Add the `org.nspasteboard.TransientType` and
   `org.nspasteboard.AutoGeneratedType` markers.
5. **Wait for modifiers to be released.** Poll `keystrokes.pressedModifiers` (HID state) every
   `pollInterval`, up to `maxPolls` times. Because the limit is a poll *count*, tests with an instant sleeper
   cannot hang. If keys are still held, the result is copy only with `.modifiersHeld`. ⌘V is never posted
   in that state, because a held ⌘ would turn the submit ↩ into ⌘↩ (a new browser tab).
6. **Post** ⌘↓ V↓ V↑ ⌘↑ from a `.privateState` event source with explicit flags, to `.cghidEventTap`. The
   key code for "v" comes from the **ASCII-capable** layout
   (`TISCopyCurrentASCIICapableKeyboardLayoutInputSource` plus `UCKeyTranslate` with ⌘ state). The fallback
   is `kVK_ANSI_V`.
7. **Submit** (optional): post ↩.
8. **Restore** after `restoreDelay` (600 ms), but only if `changeCount` still equals the value we produced.

Strategies listed for later, behind the same protocol: AX `kAXSelectedTextAttribute` set with read-back;
`CGEvent` unicode typing; pressing the target's *Edit › Paste* menu item via AX.

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
- **One coordinator owns the session.** Views emit *intents*. The coordinator decides, and then pushes
  *chrome* (everything except the text) back to the view. **Exception, by design:** the text view owns the
  text being edited. The text travels only on commit, cancel and dismiss, because round-tripping keystrokes
  would destroy the caret, undo history and IME state.
- **Every side effect sits behind a protocol (a "port").** Live adapters live in Platform and UI. Simple fakes
  live in Core (`Fakes/`). Spies and recorders live in TestSupport.
- **Single composition root.** Kit assembles everything from one `AppEnvironment` value. A debug scenario
  is just a mutation of that value before assembly.
- **Initializers have no side effects.** No observers, prompts, Carbon handlers or windows are created in
  `init`; they come in `start()` or on first use. This makes it free to construct a full live environment and
  then replace parts of it.
- **Pure core.** Domain logic imports only Foundation, plus `os` for logging.
- **Swift 6, main-actor by design.** AppKit, AX and NSPasteboard are used on the main actor. Ports are
  declared `@MainActor protocol …` explicitly, models are not `Sendable`, and there is no
  `@unchecked Sendable`. The coordinator API is **synchronous** except for the commit path, which uses
  `async` for the dismiss animation, the sleeps and the paste. No `AsyncStream` and no extra hops.
- **Access control:** cross-module API uses `package`. The only `public` symbol is `LargeTextApplication`,
  plus `LaunchConfiguration`. No `public` declaration may expose a `package` type, and the host app never
  needs `package` symbols.
- **No third-party dependencies** in v1.

### 3.2 Package layout & module graph

```
LargeText/
├── Package.swift
├── Sources/
│   ├── LargeTextCore/         Models, ports, coordinator, policies, inserters, Fakes/. Foundation only.
│   ├── LargeTextPlatform/     Live adapters: Carbon, AX, NSPasteboard, CGEvent, TIS, UserDefaults, NSWorkspace.
│   ├── LargeTextUI/           AppKit: overlay panel & editor, HUD, status item, #Previews.
│   └── LargeTextKit/          AppEnvironment, assembly, LargeTextApplication, Scenarios/ (compiled in Debug only).
└── Tests/
    ├── LargeTextTestSupport/  Spies & recorders (regular target, test-only consumers, never shipped).
    ├── LargeTextCoreTests/
    ├── LargeTextPlatformTests/
    ├── LargeTextUITests/
    └── LargeTextKitTests/
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

```swift
// swift-tools-version: 6.0
import PackageDescription

let scenarios: [SwiftSetting] = [.define("LARGETEXT_SCENARIOS", .when(configuration: .debug))]

let package = Package(
    name: "LargeText",
    platforms: [.macOS(.v14)],
    products: [.library(name: "LargeTextKit", targets: ["LargeTextKit"])],
    targets: [
        .target(name: "LargeTextCore"),
        .target(name: "LargeTextPlatform", dependencies: ["LargeTextCore"]),
        .target(name: "LargeTextUI", dependencies: ["LargeTextCore"]),
        .target(name: "LargeTextKit",
                dependencies: ["LargeTextCore", "LargeTextPlatform", "LargeTextUI"],
                swiftSettings: scenarios),
        .target(name: "LargeTextTestSupport", dependencies: ["LargeTextCore"],
                path: "Tests/LargeTextTestSupport"),          // plain library; must not import Testing
        .testTarget(name: "LargeTextCoreTests", dependencies: ["LargeTextCore", "LargeTextTestSupport"]),
        .testTarget(name: "LargeTextPlatformTests", dependencies: ["LargeTextPlatform"]),
        .testTarget(name: "LargeTextUITests", dependencies: ["LargeTextUI"]),
        .testTarget(name: "LargeTextKitTests", dependencies: ["LargeTextKit", "LargeTextTestSupport"]),
    ]
)
```
An explicit `LARGETEXT_SCENARIOS` flag is used instead of `DEBUG`. It says what it does, and it doesn't
depend on how Xcode maps custom build configurations for packages.

Toolchain: Swift Testing needs the Xcode 16+ toolchain. Plain Command Line Tools may lack `Testing`.

### 3.3 Core models (`LargeTextCore`, `package` access, bodies abbreviated)

```swift
// ── Input ──────────────────────────────────────────────────────────────
struct Modifiers: OptionSet, Hashable, Codable { command, option, control, shift }
struct KeyCombo: Hashable, Codable { var keyCode: UInt32; var modifiers: Modifiers }   // Carbon key code
enum HotkeyError: Error, Equatable { case unavailable(KeyCombo) }
enum Keystroke: Equatable { case paste, returnKey }

// ── Target ─────────────────────────────────────────────────────────────
struct TargetApplication: Equatable { let processIdentifier: Int32; let bundleIdentifier: String?; let localizedName: String }
enum ElementKind: Equatable { case singleLineText, multiLineText, secureText, notEditable }
struct ElementHandle { let raw: AnyObject }                  // AXUIElement in production; used for logging only in v1
struct FocusTarget {
    let application: TargetApplication?   // nil when LargeText itself was frontmost
    let element: ElementHandle?
    let elementKind: ElementKind?         // nil = unknown → still paste
    let selectedText: String?
    let frame: CGRect?                    // element ?? focused window; AppKit global coordinates
}

// ── Session ────────────────────────────────────────────────────────────
struct EditingSession: Identifiable { let id: UUID; let target: FocusTarget }
enum CommitMode: Equatable { case insert, insertAndSubmit }
enum CancelReason: Equatable { case userCancelled, lostFocus }        // logged

// ── Insertion ──────────────────────────────────────────────────────────
enum InsertionFallbackReason: Equatable { case permissionMissing, noEditableTarget, targetChanged, modifiersHeld }
enum InsertionOutcome: Equatable { case inserted, copiedToClipboard(InsertionFallbackReason) }
enum ClipboardRestorePolicy: Equatable { case restore(maxBytes: Int), none }
struct InsertionTiming: Equatable {
    var focusReturnDelay: Duration        // default from spike 0a (start: 50 ms)
    var pollInterval: Duration            // 20 ms
    var maxModifierPolls: Int             // 15  (≈300 ms)
    var restoreDelay: Duration            // 600 ms
    static let `default`: InsertionTiming
}
struct PasteboardSnapshot: Equatable {
    struct Item: Equatable { var dataByType: [String: Data] }
    var items: [Item]
    var isComplete: Bool
}

// ── Presentation ───────────────────────────────────────────────────────
struct FontSize: Equatable { let points: Double }
enum ZoomStep: Equatable { case bigger, smaller, reset }
enum FontSizePolicy {                                         // default 64, 24…200, step 8
    static let `default`: FontSize
    static func apply(_ step: ZoomStep, to size: FontSize) -> FontSize
}
enum TargetHint: Equatable { case willCopyToClipboard, singleLine }
struct OverlayChrome: Equatable {                             // everything the overlay draws except the text
    var fontSize: FontSize
    var targetName: String?               // "Typing into Safari"
    var targetBundleIdentifier: String?   // UI resolves the icon; Core never sees NSImage
    var targetFrame: CGRect?              // UI picks the screen
    var hint: TargetHint?
}
struct OverlayIntent: Equatable {                             // tagged with its session; stale ones are ignored
    let sessionID: UUID
    let kind: Kind
    enum Kind: Equatable {
        case commit(CommitMode, text: String)
        case cancel(CancelReason, text: String)
        case zoom(ZoomStep)
    }
}
enum Notice: Equatable {
    case copiedToClipboard(InsertionFallbackReason)
    case secureFieldUnsupported
    case hotkeyUnavailable(KeyCombo)
}

// ── Permissions ────────────────────────────────────────────────────────
enum PermissionStatus: Equatable { case granted, denied }
struct Permissions: Equatable { var accessibility: PermissionStatus; var eventPosting: PermissionStatus }
```

### 3.4 Ports (protocols) in Core

```swift
@MainActor protocol HotkeyRegistering: AnyObject {
    func register(_ combo: KeyCombo, handler: @escaping @MainActor () -> Void) throws(HotkeyError) -> any HotkeyRegistration
}
@MainActor protocol HotkeyRegistration: AnyObject { func unregister() }

@MainActor protocol FocusCapturing: AnyObject {
    func captureFocus() -> FocusTarget
    var frontmostProcessIdentifier: Int32? { get }            // pre-insertion guard
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
    @discardableResult func writeTransientString(_ string: String) -> Int   // returns the new changeCount
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
    /// `initialText` is applied once and fully selected if non-empty; afterwards the view owns the text.
    func present(sessionID: UUID, initialText: String, chrome: OverlayChrome,
                 intents: @escaping @MainActor (OverlayIntent) -> Void)
    func update(_ chrome: OverlayChrome)                     // never touches the text
    func requestCommit(_ mode: CommitMode)                   // hotkey toggle → view emits the normal .commit
    /// Stops emitting intents immediately, orders out, returns the text at that moment.
    @discardableResult func dismiss() async -> String
}

@MainActor protocol NoticePresenting: AnyObject { func show(_ notice: Notice) }
```

### 3.5 The coordinator: `EditingSessionCoordinator` (Core)

```swift
@MainActor
final class EditingSessionCoordinator {
    enum Phase: Equatable { case idle, editing(sessionID: UUID), closing(sessionID: UUID) }

    private(set) var phase: Phase = .idle
    var onPhaseChange: ((Phase) -> Void)?                     // single consumer: the status item
    private var session: EditingSession?
    private var draft: String?                                // last cancelled text, in memory only

    init(dependencies: CoreDependencies)
    func toggle()                                             // hotkey & menu
}

struct CoreDependencies {
    var focus: any FocusCapturing
    var inserter: any TextInserting
    var overlay: any OverlayPresenting
    var notices: any NoticePresenting
    var preferences: any PreferencesStore
}
```

**Transition table.** Each row is a unit test. Every exit path enters `closing` **before** awaiting anything.

| Phase | Event | Effect → next phase |
|---|---|---|
| idle | `toggle()`, target `.secureText` | notice `.secureFieldUnsupported` → idle |
| idle | `toggle()` | capture focus; initial text = selection ?? draft ?? ""; chrome.hint from target → present → **editing** |
| editing | `toggle()` | `overlay.requestCommit(.insert)` (the view answers with a `.commit` intent) |
| editing | `.commit(_, text)` with whitespace-only text | **closing** → dismiss → **idle** (draft untouched) |
| editing | `.commit(mode, text)` | **closing** → `await dismiss()` → `await inserter.insert` → notice if `.copiedToClipboard` → draft = nil → **idle** |
| editing | `.cancel(reason, text)` | **closing** → draft = text (if non-blank) → `await dismiss()` → **idle** |
| editing | `.zoom(step)` | `FontSizePolicy.apply` → persist → `overlay.update(chrome)` |
| closing | anything | ignored |
| any | intent with a stale `sessionID` | ignored |

The draft is always shown fully selected, so a Safari draft reopened over Slack is replaced by the first
keystroke and never pasted by accident. Permission changes mid-session need no special handling: the
router checks permissions at commit time.

### 3.6 Insertion composition (Core)

```swift
final class RoutingTextInserter: TextInserting {
    init(permissions: any PermissionsProviding, paste: any TextInserting, copyOnly: any TextInserting)
}
final class PasteboardTextInserter: TextInserting {
    init(pasteboard: any PasteboardClient, keystrokes: any KeystrokeSending, focus: any FocusCapturing,
         preferences: any PreferencesStore, sleeper: any Sleeper, timing: InsertionTiming = .default)
}
final class ClipboardOnlyTextInserter: TextInserting { init(pasteboard: any PasteboardClient) }
enum InsertionTextPolicy { static func prepare(_ text: String, for target: FocusTarget) -> String }
```

The ordering of guard → policy → snapshot → write → modifier polls → ⌘V → ↩ → delayed conditional restore
is tested in Core with a fake pasteboard, a recording keystroke sender and an instant sleeper. The modifier
wait is bounded by a poll count, so these tests cannot hang.

`Fakes/` in Core (tiny, Foundation-only, used by both scenarios and tests): `StubFocusCapturer`,
`FixedPermissions`, `LoggingTextInserter`, `InMemoryPreferencesStore`, `InstantSleeper`.

### 3.7 Live adapters (`LargeTextPlatform`)

| Type | Implements | Notes |
|---|---|---|
| `CarbonHotkeyRegistrar` | `HotkeyRegistering` | Installs one `InstallEventHandler` lazily. The C callback gets `Unmanaged` self, then `MainActor.assumeIsolated` (Carbon dispatches on main). |
| `AccessibilityFocusCapturer` | `FocusCapturing` | §2.4. Pure helpers, unit-tested: `AXGeometry.appKitRect(axPosition:axSize:primaryScreenFrame:)`, `ElementKind(role:subrole:)`, `AXBatchResult`. |
| `SystemPermissionsProvider` | `PermissionsProviding` | `AXIsProcessTrusted`, `CGPreflightPostEventAccess`, `AXIsProcessTrustedWithOptions`. |
| `SystemPasteboardClient` | `PasteboardClient` | Takes an `NSPasteboard` in `init` (`.general` live, a named board in tests). Pure `SnapshotTypeFilter`. |
| `CGEventKeystrokeSender` | `KeystrokeSending` | `KeyboardLayoutResolver` (ASCII-capable layout) and a `.privateState` source. |
| `UserDefaultsPreferencesStore` | `PreferencesStore` | Keys use the `LargeText.` prefix. |
| `TaskSleeper` | `Sleeper` | `Task.sleep(for:)`. |

### 3.8 UI (`LargeTextUI`)

| Type | Role |
|---|---|
| `OverlayPanel: NSPanel` | Non-activating (set in `init`), borderless, can become key, `.fullScreenAuxiliary`. |
| `OverlayWindowController` | Implements `OverlayPresenting`. Picks the screen with `ScreenResolver`. Fades for at most 120 ms and respects *Reduce Motion*. Applies the resign-key rule. Suppresses intents during its own dismiss. |
| `EditorViewController` | Backdrop, card, header (icon, "Typing into Safari", hint), `LargeTextView`, footer hints. Renders `OverlayChrome`. Maps `EditorAction` to intents or local actions. |
| `LargeTextView: NSTextView` | Key interception (§2.3) and marked-text handling. |
| `EditorKeyBindings` | Pure function `(KeyInput) -> EditorAction?`. `KeyInput { keyCode, charactersIgnoringModifiers, modifiers }`. `EditorAction { commit(CommitMode), cancel, newline, zoom(ZoomStep), standardEdit(StandardEdit) }`. `StandardEdit { undo, redo, cut, copy, paste, selectAll }`. |
| `ScreenResolver` | Pure function `(targetFrame?, mouseLocation, [ScreenDescriptor]) -> ScreenDescriptor`, where `ScreenDescriptor { id, frame, visibleFrame }`. Uses the target frame, then the screen under the mouse, then the primary screen. |
| `HUDNoticePresenter` | Implements `NoticePresenting`. A non-key `NSPanel` with large text that auto-hides after 2.5 s. |
| `StatusItemController` | The menu from §2.7. Re-reads permissions in `menuNeedsUpdate`. Driven by Kit. |
| `Theme` | All colors and metrics in one place. |
| `#Preview`s | `EditorViewController` in these states: empty, prefilled, long text, single-line hint, copy-to-clipboard hint. This is the fast loop for visual iteration (macOS 14; select the package scheme in Xcode). |

Overlay visuals (v1, deliberately simple, tuned after hands-on):
- Backdrop: black at 55% opacity.
- Card: about 80% of the screen width, `NSVisualEffectView` with `.hudWindow`, corner radius 24.
- Header: icon plus target name, at 0.4× the editor font size.
- Editor: grows up to 60% of the screen height, then scrolls.
- Footer: `↩ Insert   ⌘↩ Insert & Submit   ⎋ Cancel   ⌘± Size`, at 0.3× the editor font size.

### 3.9 Composition root, running in a given state, host app (`LargeTextKit`)

```swift
@MainActor
package struct AppEnvironment {                    // plain instances; constructing them has no side effects
    var hotkeys: any HotkeyRegistering
    var focus: any FocusCapturing
    var permissions: any PermissionsProviding
    var pasteboard: any PasteboardClient
    var keystrokes: any KeystrokeSending
    var preferences: any PreferencesStore
    var sleeper: any Sleeper
    var overlay: any OverlayPresenting
    var notices: any NoticePresenting
    var inserterOverride: (any TextInserting)?     // nil → standard Routing(Pasteboard, ClipboardOnly) composition
    var presentOnLaunch = false

    static func live() -> AppEnvironment
}

/// Assembly happens AFTER scenarios have mutated the environment, so overrides are always respected.
@MainActor
package struct AppAssembly {
    static func coreDependencies(from env: AppEnvironment) -> CoreDependencies
}
```

**Kit-owned responsibilities.** These are not ports, and scenarios do not control them:
- `LargeTextApplication.start()`:
  1. sets the activation policy;
  2. builds the coordinator from `AppAssembly`;
  3. creates the status item;
  4. registers the hotkey (on `HotkeyError`, shows a notice and the menu item);
  5. calls `requestAccessibility()` once if access is missing;
  6. presents the overlay if `presentOnLaunch` is set.
- `stop()` unregisters the hotkey and removes the status item.

**Scenarios** are compiled only with `LARGETEXT_SCENARIOS`, so Debug only. Each one is a mutation:

```swift
#if LARGETEXT_SCENARIOS
enum Scenario: String, CaseIterable {
    case overlayPrefilled  = "overlay-prefilled"   // StubFocusCapturer(Safari, selection "https://www.apple.com"),
                                                   // LoggingTextInserter, presentOnLaunch
    case noEditableTarget  = "no-editable-target"  // StubFocusCapturer(.notEditable), real clipboard → HUD
    case permissionMissing = "permission-missing"  // FixedPermissions(.denied): real routing → copy-only HUD
    case loggingInsertion  = "logging-insertion"   // everything live except LoggingTextInserter

    func apply(to env: inout AppEnvironment)
}
#endif
```
- Every scenario also swaps in `InMemoryPreferencesStore`, so real settings are never changed.
- Each scenario documents what stays live. For example, `permission-missing` still uses the real
  pasteboard, so you can see the actual copy-only behaviour.
- Visual states such as empty, long text and single-line are covered by `#Preview`s, not scenarios.

```swift
public struct LaunchConfiguration: Equatable {
    public var scenarioName: String?               // `--scenario <name>`
    public var presentOnLaunch: Bool               // `--present-on-launch`
    public static var current: LaunchConfiguration // parsed from ProcessInfo.arguments
    init(arguments: [String])                      // pure, unit-tested
}

@MainActor
public final class LargeTextApplication: NSObject, NSApplicationDelegate {
    public init(launch: LaunchConfiguration = .current)   // live() → scenario.apply (if compiled in) → assembly
    public func start()
    public func stop()
    /// Convenience for the host's main.swift: sets itself as delegate and runs NSApplication.
    public static func run(launch: LaunchConfiguration = .current) -> Never
}
```

**Host Xcode app.** Create a macOS App (AppKit) target, then:
1. Delete `AppDelegate.swift`, `Main.storyboard` and the `NSMainStoryboardFile` Info.plist key.
2. Set `LSUIElement = YES`, remove the App Sandbox capability, and keep Hardened Runtime.
3. Sign with your development team (see §6).
4. Add `main.swift`:

```swift
import LargeTextKit
LargeTextApplication.run()
```

(With `@main` on an `NSApplicationDelegate`, the delegate only gets connected when a nib or storyboard
supplies it. That is why the plan uses an explicit `main.swift`.)

Scenario schemes in Xcode: *Arguments Passed On Launch* = `--scenario overlay-prefilled --present-on-launch`.

### 3.10 Data flow: one complete commit

```
User ⌃⌥⌘T
  └─▶ CarbonHotkeyRegistrar ─(Kit wiring)─▶ coordinator.toggle()
        ├─ focus.captureFocus()      → FocusTarget{Safari, .singleLineText, selection:"apple.com", frame}
        ├─ phase = .editing(id)
        └─ overlay.present(id, "apple.com" (selected), chrome{64pt, "Safari", .singleLine}, intents)
User types (text lives in LargeTextView), presses ⌘+
  └─▶ EditorKeyBindings → .zoom(.bigger) → intent ─▶ coordinator → prefs.fontSize = 72 → overlay.update
User presses ⌘↩
  └─▶ discardMarkedText → intent(id, .commit(.insertAndSubmit, "apple.com/mac")) ─▶ coordinator
        ├─ phase = .closing(id)
        ├─ await overlay.dismiss()                (intents suppressed; Safari never stopped being active)
        ├─ await inserter.insert(...)
        │     Routing → Pasteboard: focusReturnDelay → pid guard → text policy → snapshot →
        │     write (.currentHostOnly, transient) → modifier polls → ⌘↓V↓V↑⌘↑ → ↩ →
        │     sleep 600 ms → restore if changeCount unchanged
        ├─ outcome .inserted → draft = nil
        └─ phase = .idle
```

---

## 4. Testing strategy

- **Swift Testing** (`import Testing`), with the Xcode 16+ toolchain.
- **Core:**
  - every row of the §3.5 table, including `closing` ignoring a late `.cancel(.lostFocus)` and stale ids;
  - draft prefill and selection;
  - router decisions, including unknown element → paste;
  - `PasteboardTextInserter`: ordering, pid-guard failure, `.modifiersHeld` after `maxModifierPolls`,
    conditional restore, `ClipboardRestorePolicy.none`, incomplete snapshot;
  - `InsertionTextPolicy`, `FontSizePolicy`.
- **UI (pure):**
  - `EditorKeyBindings`: ↩ vs ⇧↩ vs ⌘↩; zoom via ⌘= / ⌘⇧= / ⌘- on US and German layouts (by characters and
    by key code); standard edits; Escape;
  - `ScreenResolver`.
- **Platform (pure):** AX geometry flip against a secondary screen with a non-zero origin, `AXBatchResult`
  error unwrapping, `ElementKind` mapping, `SnapshotTypeFilter`, and a pasteboard round trip on
  `NSPasteboard(name:)` (never `.general`).
- **Kit:** `LaunchConfiguration` parsing; for each scenario, that `apply` sets the expected services
  (type checks).
- **Manual matrix** (`docs/manual-testing.md`):
  - Safari URL bar, Chrome omnibox, Firefox, TextEdit, Notes, Slack/VS Code;
  - Terminal/iTerm (newline policy), a password field;
  - full-screen video, two displays;
  - Dvorak and Russian layouts, Japanese IME;
  - ⌘Tab during a session, screen lock during a session.
- **Logging:** `os.Logger` lines with durations for each session (capture, focus return, paste, restore
  outcome). These are the numbers for the PRD.

---

## 5. Milestones

0. **Spike (half a day, throwaway branch).**
   - a) Focus returns to Safari/Chrome/Electron fields after `orderOut`; measure the delay → `focusReturnDelay`.
   - b) The overlay is visible over a full-screen video Space at `.statusBar + 1`.
   - c) ⌘V via `CGEvent` reaches the Chrome omnibox.
   - e) IME, Dictation and Character Viewer inside the panel.
   - f) ⌘Tab, Spotlight, screen lock → resign key.
   - g) Hotkey registration failure mode; the hotkey under Secure Input.
   - h) The pasteboard privacy prompt on the current macOS version.
   - i) Permission granted mid-run, with and without a relaunch.
   - j) `AXManualAccessibility` on an Electron app.
   (0d was removed: no main menu.)
1. **Package skeleton.** `Package.swift`, four library targets plus TestSupport, Core models/ports/fakes,
   empty tests passing.
2. **Vertical slice ("feel" starts here).** Uses the **final** ports and the **final** coordinator type, with
   a subset of the table: idle → editing → commit/cancel. Ports without real implementations yet use Core
   fakes. Includes the real Carbon hotkey, focus capture, overlay panel and pasteboard insertion. *You can
   start using it here.*
3. **Core hardening.** The remaining table rows (closing, stale ids, drafts, secure refusal), routing, text
   policy, guard, modifier wait, and all Core tests. *This milestone only adds rows; it does not restructure.*
4. **UI polish.** Theme, header and footer, HUD, `#Preview`s, Reduce Motion, multi-display screen choice.
5. **Kit completion.** Status menu with permission item, the four scenarios plus scheme instructions, the
   manual-testing checklist.
6. **Hands-on.** Run the manual matrix and collect opinions for the PRD.

Out of scope for v1:
- hotkey recorder and settings window, theme customization;
- prefill with the whole field, per-app insertion strategies, entry history;
- launch at login (`SMAppService.mainApp`), Sparkle updates;
- activation fallback, a dedicated permission window;
- a Mac App Store sandbox build;
- observing system events (resign-key already covers them).

---

## 6. Risks & mitigations

| Risk | Mitigation |
|---|---|
| ⌘V lands in the wrong app | Resign-key cancels the session; the pid guard after the focus-return delay falls back to copy-only. |
| Chrome/Electron expose no focused element | Unknown is treated as "paste anyway"; spike `AXManualAccessibility`. |
| The non-activating panel misbehaves in some app | Spike 0a; add an activation port only if needed. |
| Paste race (target reads the pasteboard late) | 600 ms restore delay, conditional on `changeCount`; `InsertionTiming` is injectable. |
| Pasteboard privacy prompts (macOS 15.4+ `NSPasteboard.accessBehavior` preview; enforcement announced) | Spike 0h; `ClipboardRestorePolicy.none`; any related API guarded with `if #available(macOS 15.4, *)`. |
| The snapshot forces lazy or promised data | Type filter and byte budget; lossy restore. (A time budget can't interrupt a synchronous read, so there isn't one.) |
| Clipboard managers or Universal Clipboard pick up our text | Transient markers and `.currentHostOnly` (available since 10.12). |
| Modifiers still held at paste time | HID polling bounded by a count; copy-only with `.modifiersHeld`; `.privateState` source; full ⌘ down/up sequence. |
| Non-QWERTY or non-Latin layouts | Key code from the ASCII-capable layout; zoom bindings by character and key code. |
| Multi-line paste executes commands in a terminal | `InsertionTextPolicy` plus the header hint. |
| A hung target blocks AX | 0.1 s global timeout, batched reads, AX skipped for our own pid. |
| Overlay level above system prompts | No prompts are triggered during a session. |
| Hotkey conflicts or refusals | ⌃⌥⌘T default; failure surfaced in a notice and the menu. |
| Secure Input false positives | Diagnostic only. |
| **TCC permission resets during development** | Sign Debug builds with your real team (not "Sign to Run Locally"). Never change the bundle id or signing identity between builds, because TCC keys on the designated requirement. After an intentional change, run `tccutil reset Accessibility <bundle id>`. |

---

## 7. Coding conventions

- Swift 6 language mode. Explicit `@MainActor` on ports and on UI and coordination types. No ad-hoc
  `DispatchQueue.main.async`.
- One primary type per file. Feature folders inside modules: `Hotkey/`, `Focus/`, `Insertion/`, `Overlay/`,
  `Permissions/`, `Preferences/`, `Fakes/`.
- `package` for cross-module API. `public` only for `LargeTextApplication` and `LaunchConfiguration`.
- Logging uses `os.Logger(subsystem: "LargeText", category: <module>)`.
- Process-wide singletons (`NSPasteboard.general`, `NSWorkspace.shared`, `NSApp`) are referenced only in
  adapters and in Kit.
- Errors are typed enums (typed `throws` where it helps). User-visible failures always become a `Notice`.

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
