# LargeText Reader — Technical Implementation Plan (draft 5)

> **Feature: Reader.** Point at small text anywhere on screen (a label, a menu item, a tweet, a line in a
> document) and press a shortcut. The text under the pointer appears in a large, read-only card, at the
> **same font size as the editor**.
> - **Tap** the shortcut to pin the card.
> - **Press and hold** it to make the card follow the pointer until you let go.
>
> This builds on the v1 architecture in `IMPLEMENTATION_PLAN.md`: ports, one coordinator per session, a
> single composition root, and scenarios. It reuses as much as it can: the hotkey registrar, the AX
> plumbing, the panel and its level and Spaces behaviour, the theme, the font-size policy, the HUD and the
> status item.
>
> Draft 2 includes an independent review. Draft 3 includes that reviewer's follow-up check, and draft 4 a fresh reviewer's final check.
> Draft 5 includes a fresh review **checked against the existing code**. See §11.

---

## 1. What we are building, and how it differs from macOS

**Prior art: macOS Hover Text.** It lives under *System Settings › Accessibility › Zoom › Hover Text*:
hold ⌘ and hover, and a small bubble shows the text under the pointer. Its limitations:
- The text is still fairly small and sits right next to the pointer.
- It shows one AX element, which is often too much text (a whole text area) or too little (an icon with
  no label).
- You can't pin, scroll, copy or zoom it.
- It looks dated and is hard to read from across the room.

**Reader v1:**
- uses the editor's font size and card styling, shared through the `fontSize` preference;
- picks a sensible **text unit**: the selection, else the sentence or paragraph under the pointer, else
  the element's label;
- has two gestures on one shortcut:
  - **tap = pin**: keyboard-interactive, scrollable, copyable, zoomable;
  - **hold = follow**: updates live while the pointer moves, and closes on release;
- works over full-screen video, like the editor;
- **later:** an OCR fallback for pixels with no accessibility text (video subtitles, images,
  canvas-rendered apps, games).

---

## 2. Feasibility summary

| Concern | Feasible? | API | Permission |
|---|---|---|---|
| Global shortcut, press **and** release | Yes | Carbon `RegisterEventHotKey` with `kEventHotKeyPressed` and `kEventHotKeyReleased` on one handler; route by `GetEventKind(event)` | None |
| Pointer location | Yes | `NSEvent.mouseLocation` (AppKit, bottom-left), sampled once; the global top-left point is derived with the primary-screen flip | None |
| Pointer movement while following | Yes | A `@MainActor` `Task` loop (about 60 Hz) polling the location only while following. This also catches drags, which a `.mouseMoved` monitor misses | None |
| AX element under the pointer | Yes | `AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), x, y, &el)` is *expected* to follow the window server's mouse routing and skip click-through windows (R4 confirms). `AXUIElementGetPid` then gives the owner | Accessibility |
| Fallback when the system-wide hit lands on us or fails | Yes | `CGWindowListCopyWindowInfo(.optionOnScreenOnly, …)` provides pid candidates, front to back, then an app-scoped `AXUIElementCopyElementAtPosition` per candidate. Window *names* need Screen Recording; we never read them | None / Accessibility |
| Text of a label, button or static text | Yes | One batched `AXUIElementCopyMultipleAttributeValues` read of role, subrole, title, description, help, placeholder, number of characters, position and size. **Not `value`**: on a text area that is the whole document; it is fetched separately, only when short (§4.3) | Accessibility |
| Sentence, line or paragraph under the pointer in a native text view | Yes (AppKit/TextKit and many others) | Parameterized attributes `kAXRangeForPositionParameterizedAttribute`, `kAXStringForRangeParameterizedAttribute` (a **window** around the index), `kAXBoundsForRangeParameterizedAttribute`, plus `kAXNumberOfCharactersAttribute` | Accessibility |
| The same in web content (Safari, Chrome, Firefox, Electron) | Best effort | Text-marker attributes on the `AXWebArea`: `AXTextMarkerForPosition`, `AXSentence…`, `AXLine…`, `AXParagraphTextMarkerRangeForTextMarker`, `AXStringForTextMarkerRange`, `AXBoundsForTextMarkerRange`, `AXSelectedTextMarkerRange`. They are undocumented but stable: VoiceOver relies on them and WebKit, Chromium and Gecko implement them | Accessibility |
| Pixels only (OCR, phase 2) | Yes | ScreenCaptureKit `SCScreenshotManager.captureImage(contentFilter:configuration:)` with our app excluded, plus Vision `VNRecognizeTextRequest` | Screen Recording |
| Large card over everything, including full-screen video | Yes | The existing `OverlayPanel` (level and `collectionBehavior`) | None |

**Accessibility is the only requirement for v1.** The reader never posts events. Screen Recording is
requested only when the user enables OCR.

---

## 3. Interaction design

### 3.1 The gesture: one shortcut, tap vs. hold

The default shortcut is **⌃⌥⌘R**: R for *read*, next to the editor's ⌃⌥⌘T. It can be changed in
`PreferencesStore.readerHotkey`. A combo equal to the editor's is rejected by `HotkeyConflicts` in Kit
(§4.10): the reader isn't registered, and `hotkeyUnavailable` is reported.

```
            press                         release < holdThreshold (300 ms)
  idle ───────────────▶ following ─────────────────────────────────────▶ pinned
   ▲                       │ release ≥ holdThreshold                     │
   │                       │ press (= missed release, per R1)            │ press / ⎋ / backdrop click /
   │                       │ maxFollowDuration (30 s)                    │ resign key / editor shortcut
   └──────────────────── closing ◀───────────────────────────────────────┘
```

**Timing comes from the key events, not from when the coordinator runs.**
- The Carbon callback stamps every event with the event's own time, `GetEventTime(event)` (system uptime
  in seconds), and delivers `HotkeyEvent(phase:, at:)`. A busy main thread therefore can't skew the
  stamps.
- `ReaderGesture` is a pure state machine. It compares those timestamps, so a slow read or a busy main
  actor can't turn a tap into a hold.
- **Synthetic closes carry no timestamp.** The stuck-key check, the 30 s cap, ⎋, a backdrop click,
  resign-key, `.permissionMissing` and `close()` from `AppController` all feed `ReaderGesture` a
  `.forceClose(reason)` input. It is valid in **any non-idle phase**, so Core needs **no clock**.
- **The poll guarantee comes from scheduling, not from restricting `.forceClose`.** The coordinator only
  *starts* the key-state check once `holdThreshold + 100 ms` has passed. That delay and the 30 s cap are
  scheduled with the existing `Sleeper` port. Tests need a sleeper that parks **every** sleep until
  released: `RecordingSleeper.heldDuration` becomes `heldDurations: Set<Duration>` with
  `release(_ duration:)`. With today's single held duration, the second sleep would return at once and
  force-close every test session.
- `holdThreshold` (default 300 ms) is a preference, `readerHoldThreshold`, and a launch argument, so open
  question 4 can be answered by trying values.

**Auto-repeat:** R1 decides.
- If Carbon sends **no** auto-repeat presses, a `pressed` arriving while *following* is treated as a
  missed release, and the reader closes.
- If it **does**, every `pressed` while following is ignored. Lost releases are then caught only by the
  `keyState` poll or the 30 s cap.

A time-interval filter is not used, because it can't tell a repeat from a deliberate fast double-press.

**Stuck-key protection:**
- While following, the existing 60 Hz pointer tick also asks the narrow port
  `KeyStateReading.isPhysicallyDown(combo) -> Bool?` whether the key is still down. There is no second
  timer.
  - The live adapter uses `CGEventSource.keyState(.combinedSessionState, key:)`.
  - If R1 shows that call is gated by Input Monitoring, the adapter falls back to
    `CGEventSource.flagsState(.hidSystemState)`, which v1 already uses without Input Monitoring. In that
    mode, "any of the combo's modifiers is up" counts as released; a held ⌃⌥⌘R always has all three down.
- **The poll never decides tap vs. hold.** It starts only once `holdThreshold + 100 ms` has passed since
  the press. Its synthetic release can therefore only close a session that is already a hold.
  - The poll's own timestamp is late by up to one tick, so a tap released at 280 ms could otherwise be
    seen at 300 ms or later and counted as a hold.
  - Before that point, only Carbon's real release, with the event's own timestamp, classifies the
    gesture.
  - A real Carbon release arriving after a poll-created close is ignored.
- `maxFollowDuration` (30 s) is the last resort.

**Press while pinned:** closes the reader on key-down. The matching release is ignored.

**Release before the first read finishes:**
- *Tap:* the card is presented directly as *pinned* when the read arrives.
- *Hold* (release ≥ threshold before any card was shown): the read is cancelled and nothing is shown.

**Single source of truth.** `ReaderGesture.handle(_ input) -> [ReaderEffect]` owns **every** phase change.
The coordinator never sets a phase itself; it only executes effects, so the two can't drift.
- **Phases:** `idle`, `following`, `pinnedAwaitingFirst` (a tap released before read #1 returned),
  `pinned`, `closing`.
- **Inputs:** `.pressed(at:)`, `.released(at:)`, `.forceClose(reason)` (any non-idle phase),
  `.firstResultArrived`, `.dismissed` (closing → idle, after the presenter's fade).
- **Effects:** `startFollowing`, `pin`, `presentPinnedOnArrival`, `startKeyStateCheck`, `close(reason)`,
  `ignore`.

**Further transitions** (each one is a test):

| Phase | Event | Effect |
|---|---|---|
| closing | press | ignored; its release, arriving in idle, is ignored too |
| following → pin (tap) | displayed or arriving result is `.nothing` | dismiss + HUD "No readable text under the pointer" |
| following → pin (tap) | result is `.hidden` | pinned "Hidden text" card |
| following | a read returns `.permissionMissing` (trust revoked) | close + HUD once; no card |
| pinnedAwaitingFirst | read #1 (same `seq`) arrives | `.firstResultArrived` → present pinned (or HUD + close for `.nothing`) |
| pinned | any read result arrives | dropped (session or phase check) |

### 3.2 Two presentation modes

| | Following (hold) | Pinned (tap) |
|---|---|---|
| Panel key? | **Never.** Shown with `orderFrontRegardless()`; the target app keeps keyboard and hover state | **Yes.** `makeKey()` on the non-activating panel, like the editor |
| Mouse | `ignoresMouseEvents = true` (click-through) | Accepts clicks; a backdrop click closes |
| Backdrop | None | Dimmed, fading in when the card is pinned |
| Card position | The half of the screen away from the pointer, with hysteresis (§4.6) | Keeps its origin and anchor edge and may grow (§4.6); centred on a direct pin |
| Text unit | Sentence (preference `followingUnit`) | Paragraph (preference `pinnedUnit`), expanded without a new AX read (§4.3) |
| Overflow | Scrolled so the pointer's line is centred | Scrolls freely |
| Source highlight | Outline around the source range or element | Stays at the frozen source |
| Updates | One read in flight at a time; the newest pointer position wins (§4.4) | None |

### 3.3 Which text is shown

A pure Core function makes the decision (`ReadTextChooser`); Platform only gathers data in stages that
Core asks for (§4.3).

1. **Hidden content:** show the "Hidden text" card. This applies to:
   - any visited element with subrole `AXSecureTextField` (via the existing `ElementKind.classify`);
   - any app on the denylist (§4.10).

   The check applies to the hit element **and every element visited in the walks**.

   **The denylist is checked first, in Platform.** The coordinator snapshots a Sendable
   `ReadPolicy { denylist, elementTextLimit, maxCharacters }` once per session and passes it to every
   `read`. In v1 these values are constants (the denylist is hard-coded, §4.10); the snapshot is where
   preferences will feed in later. The reader actor returns `.hidden` as soon as the hit test resolves the pid and
   bundle ID, **before stage 0**, so no string is ever fetched from a denylisted app. The chooser repeats
   the check as defence in depth.
2. **Selection under the pointer:**
   - native: `kAXSelectedTextRangeAttribute` plus `kAXBoundsForRange…` to check the pointer is inside;
   - web: `AXSelectedTextMarkerRange` on the `AXWebArea` plus `AXBoundsForTextMarkerRange`.
3. **Unit at the pointer:** a sentence (following) or a paragraph (pinned), taken from a text window
   around the pointer index (native) or from text markers (web).
4. **Element text or control name and value:** a non-blank `value` is usable only when it is
   ≤ `elementTextLimit` (500 characters).
   - **Text-value roles** (`AXStaticText`, `AXTextField`, `AXTextArea`, `AXComboBox`, `AXCell`, and a
     missing role): show the short value first, then fall back to the label in rung 5.
   - **All other roles:** the name is the first non-blank title, then description. If a name and a
     short value exist and differ after trimming and case-insensitive comparison, show `name + "\n" + value`.
     If only the name exists or the value equals it, show the name once. Without a name, show the short
     value alone. Help and placeholder are fallbacks, never names for this combination.
   - A name, alone or combined, uses source `.label`; a value alone uses `.element`. Both use the
     element frame and the usual verbatim, outer-trimmed, capped display-text path below.
   - `value` is fetched only by the `.value` step, which `ReadPlan` emits when `characterCount` is known
     and ≤ `elementTextLimit`, or when the length is unknown and the role isn't a text area or text field
     (§4.3). A control's title or description does not skip this attempt. `nonTextValueRoles` remain
     excluded: checkbox state, slider numbers and link URLs are never fetched or shown.
5. **Fallback label:** title, then description, then help, then placeholder. For controls, rung 4 has
   already tried the name and value, so only help and placeholder remain before the walk. This covers
   buttons, menu items, toolbar icons, tabs and Dock items.
6. **Bounded walk** when the hit element is a container without text (`AXGroup`, `AXCell`, `AXRow`, or an
   `AXLink` around `AXStaticText`):
   - down at most 2 levels and 20 children per level, via `AXUIElementCopyAttributeValues(el,
     kAXChildren, 0, 20, …)`;
   - up at most 2 levels, for a labelled ancestor.
7. **(Phase 2) OCR** around the pointer.
8. **Nothing found:**
   - following: a quiet "No text here" card, so the user can move on to text;
   - tap: the HUD "No readable text under the pointer", then close.

Text is shown verbatim, with only the outer whitespace trimmed, and is capped at `maxCharacters`
(4 000, ending in an ellipsis).

---

## 4. Key technical decisions

### 4.1 Hotkey: extend the Carbon registrar with key-up

```swift
package enum HotkeyPhase: Sendable { case pressed, released }
/// `at` is `GetEventTime(event)`: seconds of system uptime, taken from the Carbon event itself.
package struct HotkeyEvent: Sendable, Equatable {
    package var phase: HotkeyPhase
    package var at: TimeInterval
    package init(phase: HotkeyPhase, at: TimeInterval)
}

@MainActor
package protocol HotkeyRegistering: AnyObject {
    func register(_ combo: KeyCombo,
                  handler: @escaping @MainActor (HotkeyEvent) -> Void) throws(HotkeyError) -> any HotkeyRegistration
}

extension HotkeyRegistering {
    /// Press-only convenience for the editor. It has a distinct name, so overload resolution between two
    /// trailing-closure signatures can't silently pick the wrong one.
    package func registerPressOnly(_ combo: KeyCombo,
                                   _ onPress: @escaping @MainActor () -> Void) throws(HotkeyError) -> any HotkeyRegistration
}
```

`CarbonHotkeyRegistrar` changes:
- installs an `EventTypeSpec` array of two entries, pressed and released;
- the callback is renamed `carbonHotKeyEventCallback`, branches on `GetEventKind(event)`, and stamps the
  time **inside the callback** with `GetEventTime(event)`;
- a test seam: an internal `handle(hotKeyID:kind:time:)` plus an internal `insertHandlerForTesting`, so
  `CarbonHotkeyRegistrarTests` (`@testable import`) can route events without calling the real
  `RegisterEventHotKey`;
- `SpyHotkeys`: `register(_:handler:)` and `Registration.handler` change to `(HotkeyEvent) -> Void`, and
  it gains `simulate(_ phase:, at:)`;
- the editor's call site in `AppController.start()` changes explicitly to `registerPressOnly`.

**Model convention (all new Core models):** `package var` properties and an explicit `package init`, as
the existing models do (`OverlayChrome`, `ScreenDescriptor`). Memberwise initializers are internal, and
Platform, UI and TestSupport must be able to build these values. This applies to `HotkeyEvent`,
`PointerSample`, `ReadCandidates`, `TextWindow`, `TextSpan`, `ReadText`, `ReadPolicy` and
`ReaderContent`.

**Call sites that break in M0** (all updated in the same change):
- `AppController.start()`'s editor hotkey registration;
- `SpyHotkeys.register` and `SpyHotkeys.Registration.handler`;
- `ScenarioTests.environment()` and `AppEnvironmentTests`, which build `AppEnvironment` positionally.
  The new `AppEnvironment` init parameters get defaults, so these keep compiling.

A modifier-only hold (e.g. holding right ⌥) would need a `CGEventTap` with Input Monitoring. It is not in
v1.

### 4.2 Hit testing

1. **Sample the pointer once, in Platform**, as a `PointerSample`:
   - `appKit`: `NSEvent.mouseLocation`, sampled once;
   - `global`: top-left coordinates for CG and AX, **derived** from `appKit` with the primary-screen flip
     that `AXGeometry` already implements. Two separate samples could disagree by a tick.

   From there on, AX/CG code only uses `global`, and UI code only uses `appKit`.
2. **System-wide hit test first:**
   `AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), global.x, global.y, &el)`, then read
   the owner with `AXUIElementGetPid`. If the pid isn't ours, use the element.
3. **Fallback, built only if R4 requires it:** the hit returned our own pid (our card or highlight) or
   failed. Until R4 says otherwise, an own-pid hit is **"no update"** while following, so the last result
   stays and "No text here" doesn't flash. On a tap it counts as `.nothing`.
   - `WindowHitTester` lists on-screen windows front to back that contain the point and aren't ours. This
     filter is a pure function over `[WindowInfo]`.
   - For each candidate pid, up to **3**, run an app-scoped
     `AXUIElementCopyElementAtPosition(AXUIElementCreateApplication(pid), …)` until one returns an element.
   - WindowServer and pids AX can't serve are skipped.
   - The lookup costs about 5–20 ms, which is why it is only a fallback.
4. Because reads run **off the main thread** (§4.4), an AX request that happens to land on our own
   process doesn't deadlock: the main thread is free to answer it.
5. **Spike R4:** with `ignoresMouseEvents = true`, does the system-wide hit test already skip our panel?
   If yes, the fallback almost never runs.

### 4.3 Staged extraction: Core decides, Platform fetches

Reading every attribute on every read would cost 15–40 cross-process calls, so extraction is staged.

```swift
/// All rects are AppKit global coordinates: Platform converts exactly once, at its boundary.
package struct ReadCandidates: Sendable, Equatable {
    var pid: Int32, bundleID: String?
    var role: String?, subrole: String?
    var title: String?, description: String?, help: String?, placeholder: String?
    var value: String?                // only filled by ReadStep.value (never in stage 0)
    var characterCount: Int?
    var elementFrame: CGRect?
    var selection: TextSpan?          // set only if the pointer is inside it
    var window: TextWindow?           // text around the pointer + offsets
    var markerUnits: [ReadGranularity: TextSpan]  // web path: unit → text + bounds
    var childTexts: [String]
    var ancestorLabel: String?
    var hiddenEncountered: Bool       // a secure element was seen in the walks
    var supportedParameterized: Set<String>   // AXUIElementCopyParameterizedAttributeNames on the hit element
    var webArea: Bool                 // see below
    var attemptedSteps: Set<ReadStep> // ReadPlan never returns a step in here → the loop always ends
}
package struct TextWindow: Sendable, Equatable {
    var text: String                  // ≈ index ± 2 000 UTF-16 units, clamped to characterCount
    var start: Int                    // UTF-16 offset of `text` in the element
    var indexAtPointer: Int           // UTF-16 offset in the element
}
package enum ReadStep: Sendable, Hashable { case value, selection, textWindow, textMarkers, walk, done }
```

- **Stage 0** (always): one `AXUIElementCopyMultipleAttributeValues` batch with role, subrole, title,
  description, help, placeholder, `kAXNumberOfCharactersAttribute`, position and size, plus one
  `AXUIElementCopyParameterizedAttributeNames`. This is the same `AXBatchResult` helper the focus capturer
  uses.
  - **No `value` in stage 0.** On an `AXTextArea`, `value` is the whole document (Terminal scrollback, an
    Xcode file, a Mail thread), often megabytes over IPC, on every following read. `ReadStep.value`
    fetches it only when short (§3.3 step 4).
  - **`webArea`** is true when `supportedParameterized` contains `AXTextMarkerForPosition`. For browser
    and Electron pids only, if it is false, one parent walk looks for an `AXWebArea`.
- **Then** the pure `ReadPlan.next(after: candidates, granularity:) -> ReadStep` (Core) names the next expensive
  step, or `.done`. Examples:
  - a short native `AXStaticText` → `.value` → `.done`;
  - `webArea == true` (even for a short static text, which would otherwise return a fragment like "here"
    from the middle of a sentence) → `.textMarkers`;
  - an `AXTextArea` with 1 M characters → `.selection`, then `.textWindow`. Never `.value`;
  - an empty `AXGroup` → `.walk`.
- Platform runs that step, adds it to `attemptedSteps`, merges the result into `ReadCandidates` and asks
  again. A step that is unsupported (not in `supportedParameterized`) or fails leaves its fields nil.
  Because `ReadPlan` never repeats an attempted step, the loop always reaches `.done`.
- `ReadTextChooser` gets the final candidates.

**Native text window (instead of fetching the full text):**
```
kAXRangeForPositionParameterizedAttribute(AXValue(CGPoint global)) → CFRange → indexAtPointer
kAXStringForRangeParameterizedAttribute(CFRange(index − 2000 … index + 2000, clamped)) → window text
kAXBoundsForRangeParameterizedAttribute(chosen unit range) → highlight rect (converted to AppKit)
```
`TextSegmenter` (Core, pure) finds the sentence, line or paragraph inside the window with
`enumerateSubstrings(options: .bySentences / .byParagraphs / .byLines)` and maps it back to element
offsets. This works the same for Terminal scrollback, Xcode files and long mail threads.

**Pinning expands to the paragraph:**
- **Native:** a `ReadText` keeps its `TextWindow`, so going from the following unit (sentence) to the
  pinned unit (paragraph) is a pure re-segmentation in Core. The only extra AX call is one
  `BoundsForRange` for the new highlight, which is optional.
- **Web (v1):** marker ranges can't be re-segmented locally, so on pin **the web sentence stays**.
  - **Deferred until hands-on shows it matters:** one extra paragraph read on pin. It would call
    `read(at:granularity: .paragraph, pid: frozenPid, policy:)` and be tagged `(sessionID, pinSeq)` as the
    one result accepted while pinned. The `pid` parameter is kept in the port for it.
  - Fetching both units on every following read was rejected: it adds two calls to every read for a
    benefit seen only at pin time.
  - **Gecko fallback (R5):** if sentence ranges are missing, fetch the paragraph or line marker string and
    segment it locally with `TextSegmenter`.

**Web path:** `AXTextMarkerReader` walks up to the `AXWebArea`. It then runs
`AXTextMarkerForPosition` → `AX{Sentence,Paragraph,Line}TextMarkerRangeForTextMarker` →
`AXStringForTextMarkerRange` and `AXBoundsForTextMarkerRange`, plus `AXSelectedTextMarkerRange` for the
selection. It lives in its own file because these attributes are undocumented.

**Parameterized-attribute support** comes from the stage-0 `AXUIElementCopyParameterizedAttributeNames`
of the hit element, so unsupported steps are skipped instead of timing out. **There is no support cache in
v1.** A cache keyed by `(pid, role)` would be wrong for browsers and Electron: in one Safari pid, a toolbar
`AXStaticText` has no text markers while a web-content one does. Add a per-element cache only if R6 shows
the call is costly.

**Error policy:**
- The first `kAXErrorCannotComplete` aborts the whole read.
- `kAXErrorAttributeUnsupported` and `kAXErrorNoValue` just leave the field `nil`.
- **Per-pid back-off (skip a pid for 1 s after `cannotComplete`) is added only if R6 shows it is
  needed.** If added, the first read after setting `AXManualAccessibility` is exempt, so it can't block
  the 200 ms retry (§4.11).

### 4.4 Threading, latency and stale results

**Decision: AX reads run off the main actor, on their own serial thread.** The package enables
`ApproachableConcurrency` (which includes `NonisolatedNonsendingByDefault`), so a plain `async` method
would still run on the caller's main actor. The live reader is therefore an actor with a custom
executor:

```swift
package actor AccessibilityTextReader: TextReading {
    private let queue = DispatchSerialQueue(label: "LargeText.reader.ax", qos: .userInteractive)
    package nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }
    // AXUIElement values never leave this actor; only Sendable ReadCandidates / ReadResult do.
    package func read(at pointer: PointerSample, granularity: ReadGranularity,
                      pid: Int32?, policy: ReadPolicy) async -> ReadResult
}

package protocol TextReading: Sendable {          // protocol requirements can't have default arguments
    func read(at pointer: PointerSample, granularity: ReadGranularity,
              pid: Int32?, policy: ReadPolicy) async -> ReadResult
}
extension TextReading {
    package func read(at pointer: PointerSample, granularity: ReadGranularity,
                      policy: ReadPolicy) async -> ReadResult {
        await read(at: pointer, granularity: granularity, pid: nil, policy: policy)
    }
}
```

`TextReading` is a `Sendable` protocol that is **not** `@MainActor`. Blocking AX calls sit on that one
dedicated thread, not on the cooperative pool and not on the main thread.

**Messaging timeout:**
- The 0.1 s AX messaging timeout is process-wide. Today it is set lazily, and only by the focus capturer.
  If the reader ran first, the default timeout (about 6 s) would apply, and one hung app would stall the
  serial queue for seconds.
- So the timeout gets one home: a Platform function, `AXConfiguration.applyMessagingTimeoutIfNeeded()`.
  It calls `AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.1)` and remembers success
  behind an `OSAllocatedUnfairLock<Bool>` (macOS 13+; `Mutex` needs macOS 15 and the package targets 14).
  The call may fail with `.apiDisabled` while the app isn't trusted.
  - There is no trust observer to hook. Instead, the call is idempotent and made from three places:
    `AppController.start()` at launch, the start of each reader `read`, and `captureFocus`.
  - `AXAppPreparer` does **not** set it.
- The existing lazy call in the focus capturer is replaced by `applyMessagingTimeoutIfNeeded()`.

**Worst case:** a read can't be cancelled in the middle of an AX call. After release, a read still
running against a slow app can delay the next session's first read by about 0.1–0.2 s. This is bounded
by the timeout and abort-on-`cannotComplete`, and R6 checks it.

**Cancellation and the 200 ms retry:**
- The coordinator **cancels** the read `Task` when the session ends or the reader pins.
- The reader checks `Task.isCancelled` before each stage and after the 200 ms retry sleep (§4.11), so a
  cancelled read gives up between AX calls.
- The retry sleep suspends the actor, so other reads may run in between. That is fine: each result is
  still checked against its `seq`.
- With the retry, the worst case for a first read is about 0.4 s.

**The coordinator issues reads:**
- **One read in flight.** Every pointer tick goes to `presenter.pointerMoved(_:)` for placement (§4.6).
  Ticks while a read runs also replace `pendingPoint`. When the read
  returns, another read starts if `pendingPoint` passes `PointerThrottle`.
- `PointerThrottle` (pure): at least 60 ms since the last read **and** (moved > 4 pt **or** left the last
  element or highlight frame).
- **Every read is tagged `(sessionID, seq)`.** A result is dropped if the session ended, the phase is no
  longer *following*, or a newer `seq` has already been displayed.
- On pin, the coordinator freezes on the **last displayed** result and ignores any read still in flight.
- Duplicate results (same text and frame) are dropped, so nothing flickers.

**Budgets:**
- first card within 100 ms of key-down in typical apps;
- following updates under 50 ms per read;
- logged per read: duration, ladder step and number of AX calls.

Spike R6 checks these against real apps before the port signatures are frozen (M0).

### 4.5 The reader panel: reuse `OverlayPanel`

- `OverlayPanel` gains `var allowsKey = true`, which backs `canBecomeKey`. The reader uses its own
  instance with `allowsKey = false` while following and `true` when pinned.
- **Panel size depends on the mode.**
  - Following: the panel frame is **the card frame only**. A full-screen panel, even one ignoring mouse
    events, could make the system-wide hit test land on our own pid (R4) and turn the slow fallback into
    the normal path.
  - Pinned: the panel expands to `screen.frame` for the backdrop, with the card at the same screen
    position.
- While following, the card is shown with `orderFrontRegardless()`; `makeKeyAndOrderFront` is never
  called, because our app is inactive.
- Pin: set `allowsKey = true` and `ignoresMouseEvents = false`, show the backdrop, call `makeKey()`, and
  start the resign-key → `.close(.lostFocus)` rule.
- No `sharingType` change by default; the reader behaves like the editor (§4.10).
- **Content:** the existing `CardView` and `BackdropView`, plus a `ReaderTextView: NSTextView`:
  - `isEditable = false`, `isSelectable = true`, `isRichText = false`;
  - the same font (`Theme.editorFont(size:)`) and colours as the editor;
  - inside an `NSScrollView`.
- The header (app icon and "Reading from Safari") is extracted from `EditorViewController` into a shared
  `CardHeaderView`.
- **Footer:**
  - pinned: "⎋ Close · ⌘C Copy · ⌘± Size";
  - following: "Release to close · Tap to pin".
- **Keys, pinned only:** the pure `ReaderKeyBindings.action(for: KeyInput) -> ReaderAction?`.
  - ⎋ → close.
  - ⌘= / ⌘+ / ⌘- / ⌘0 → zoom. The whole ⌘-shortcut matcher (the private `Shortcut`, `resolve(shift:)` and
    the character-vs-key-code rule) is extracted from `EditorKeyBindings` into a shared
    `CommandShortcutMatcher`, so the reader's ⌘C and ⌘A get the same layout handling.
  - ⌘C / ⌘A → direct `copy(nil)` / `selectAll(nil)` from `ReaderTextView.performKeyEquivalent`. This is
    needed because the package never installs `NSApp.mainMenu`, the same reason `LargeTextView` does it.
- Fades respect Reduce Motion. Text updates while following are not animated.

**`ReaderPresenting` port** (`@MainActor`):
```swift
package enum ReaderContent: Sendable, Equatable {
    case text(String, scrollToUTF16: Int?)   // scroll so this offset's line is visible (following overflow)
    case hidden, nothing
}
package protocol ReaderPresenting: AnyObject {
    func present(sessionID: UUID, content: ReaderContent, chrome: ReaderChrome,
                 intents: @escaping @MainActor (ReaderIntent) -> Void)
    func update(content: ReaderContent, chrome: ReaderChrome)
    func pointerMoved(_ sample: PointerSample)            // every tick while following: drives placement hysteresis
    func pin(content: ReaderContent, chrome: ReaderChrome) // the pinned unit and source frame change at pin
    func dismiss() async
}
```

### 4.6 Placement while following: `ReaderPlacement` (pure, UI)

- **Inputs:** the screen's `visibleFrame`, the pointer, the source frame, the card's preferred size and
  the **previous card frame**.
- The screen comes from the existing `ScreenResolver.resolve(targetFrame: nil, mouseLocation:, screens:)`; no new
  overload is needed.
- Width is `Theme.cardWidthFraction`. Height fits the text, capped at `Theme.followingMaxHeightFraction`
  (45%).
- The card starts in the vertical half that **doesn't** contain the pointer, avoiding the source frame
  where possible.
- **Hysteresis:** the card changes halves only when the pointer enters the current card frame plus a
  24 pt margin, never just because it crossed the middle of the screen. It is evaluated on **every pointer
  tick** via `ReaderPresenting.pointerMoved(_:)`, not only when a new result arrives. Duplicate results
  are dropped, so a pointer moving onto the card over the same source element would otherwise never move
  it.
- Moving to another display re-resolves the screen and places the card fresh.
- **Pin:** the card keeps its **origin and anchor edge**: the top edge for a card in the top half, the
  bottom edge for a card in the bottom half. The height may grow to fit the paragraph, up to the pinned
  cap (`Theme.editorMaxHeightFraction`); anything beyond scrolls. Only then are the backdrop and key
  status added.
- **Direct pin** (a tap released before the first read returned): there is no previous frame, so
  `ReaderPlacement` runs with `previous: nil` in pinned mode, which centres the card like the editor.

### 4.7 Source highlight

`HighlightPanel` is a borderless, click-through, non-key panel at the same level. It draws a 3 pt rounded
outline in `Theme.hintColor` around the bounds of the unit or element being read. It is optional: if an
app reports bad bounds, the outline is skipped for that read.

The highlight sits **under the pointer by design**, so it is part of spike R4. If the system-wide hit
test does *not* skip click-through windows, the highlight is drawn as **four thin edge windows** (top,
bottom, left, right). These never cover the point being read, so the system-wide hit test stays the
normal path.

### 4.8 Interplay with the editor (no new type)

Both coordinators expose `isIdle`. `AppController`:
- **Reader hotkey:** ignored unless `editor.isIdle`.
- **Editor hotkey:** `await reader.close()` first, then `editor.toggle()`. The reader panel is gone, and
  never held key status while following, before `captureFocus()` runs.
- **`close()` is idempotent and awaits the in-flight dismissal.** The coordinator stores its dismiss `Task`,
  and a second `close()` awaits the same task instead of returning early. Otherwise this sequence happens:
  1. A second editor press lands during the reader's fade.
  2. That press's `close()` returns at once and it opens the editor.
  3. The first press's task finishes its fade and calls `toggle()` again.
  4. That second `toggle()` commits, and the editor flashes shut.
- **Synchronous in-flight guard.** `AppController` holds `private var editorOpenTask: Task<Void, Never>?`.
  `openEditorClosingReader()` returns at once while it is non-nil. Otherwise it stores
  `Task { await reader.close(); await editor.toggle() }` **synchronously, in the handler**, and the Task
  clears the field after `toggle()` returns. A second press that arrives before the first Task has even
  started is therefore ignored. Checking `reader.isClosing` would miss that window, because the Task hasn't
  entered `closing` yet. When the reader is idle, `close()` doesn't suspend, so "second editor press
  commits" keeps working.
- **Every editor entry point** (hotkey, status menu, present-on-launch) goes through the same
  `openEditorClosingReader()` path.

### 4.9 OCR fallback (phase 2, opt-in)

- Runs only when the AX reader finds nothing, **or** on an explicit variant (⇧ added to the shortcut),
  **and** only if `preferences.readerOCR == true`.
- **Capture:** a band around the pointer, using the element frame if there is one, else 900 × 240 pt.
  - Always `captureImage(contentFilter:configuration:)`, with a filter that **excludes our app**, so our
    own card and highlight are never recognised. `captureImage(in:)` (15.2+) has no filter and isn't used.
  - Cached `SCShareableContent`, refreshed on `NSApplication.didChangeScreenParametersNotification`.
  - `sourceRect` is **display-local, top-left origin, in points**, while `ReadCandidates` rects are in
    AppKit coordinates. Convert AppKit → global top-left (`AXGeometry`), then subtract the `SCDisplay`
    frame. Tested in `AXGeometryTests`.
  - `configuration.width/height` = `sourceRect` size × `SCShareableContent.info(for:).pointPixelScale`.
    Otherwise Vision gets a downscaled image.
  - The macOS 15 Swift `RecognizeTextRequest` is an option behind `#available`.
- **Recognition:** `VNRecognizeTextRequest` with `.accurate`, `usesLanguageCorrection` and
  `automaticallyDetectsLanguage`. The pure `OCRLineMerger` (Core) picks the observation under or nearest
  the pointer and merges vertically adjacent lines into a paragraph.
- **Images stay in memory only.** They are never written to disk or logs.
- **Permission:** `CGPreflightScreenCaptureAccess()`, and `CGRequestScreenCaptureAccess()` only from the
  status menu, never during a session.
- **Composition:** `FallbackTextReader(primary:fallback:)` in Core, tested with stubs.
- **Spike R7** measures `SCShareableContent` and capture plus recognition latency separately (target
  < 250 ms), and the re-confirmation prompts on current macOS.

### 4.10 Privacy, permissions and logging

- **Hidden content** (shown as a "Hidden text" card):
  - secure fields;
  - a default **bundle-ID denylist** of password managers and keychains, which show revealed passwords
    and 2FA codes as plain `AXStaticText`: 1Password, Bitwarden, Keychain Access, Passwords.app, …
    In v1 this is a **hard-coded default list**. A user-editable `readerDenylist` is deferred.
- **Logging rule:** log role, subrole, ladder step, text *lengths*, durations, AX error codes and bundle
  ID. Never log any AX string attribute (value, title, description, help, placeholder, selection), even
  at debug level.
- **Screen-sharing exclusion is deferred.** `sharingType = .none` is reported to be ignored by
  ScreenCaptureKit capture on recent macOS, and sharing on purpose (remote help, FaceTime with family) is
  a real couch use case. The manual checklist records how the panels appear in recordings and shares.
  The `readerHideFromScreenSharing` preference waits for that evidence.
- **Accessibility missing:** HUD "Allow Accessibility to read text" plus the existing "Grant Access…"
  status-menu item.
- `Permissions.screenRecording` is added in phase 2.
- **Status menu:** "Read Text Under Pointer (⌃⌥⌘R)" shows the HUD "Point at text and press ⌃⌥⌘R". The
  pointer is on the menu at that moment, so reading would be pointless. A keyboard-focus reading mode is
  deferred (§10).
- **Hotkey conflicts:**
  - A `get set` preference setter can't refuse a value, and `defaults write` bypasses it anyway. So the
    check moves to a pure helper, `HotkeyConflicts.validate(editor:reader:)`, which `AppController` calls.
    An equal combo means the reader isn't registered and `.hotkeyUnavailable` is reported.
  - `StatusMenuModel` and `StatusItemController.hotkeyUnavailable` change from one `KeyCombo?` to a list
    `[KeyCombo]`.

### 4.11 Making other apps expose their accessibility tree, scoped and logged

- `AXManualAccessibility` is set **only for the pid being read**, and only after a hit test returned an
  empty `AXWebArea` or `AXGroup`, or no element. It is set once per pid and logged.
- Detection:
  - Electron: the existing `ElectronAppDetector`;
  - Chromium browsers: bundle IDs (Chrome, Chrome Canary, Arc, Brave, Edge, Vivaldi, Opera).
- `AXEnhancedUserInterface` is still never set.
- This logic moves out of `AccessibilityFocusCapturer` into `AXAppPreparer`, a small type that is *not*
  `Sendable`. There are **two instances on purpose**: one inside the reader actor and one owned by the
  focus capturer on the main actor. Each tracks the pids it has prepared. Setting the attribute twice on
  one pid is harmless.
- **The tree builds asynchronously.** The first read right after enabling the attribute is usually empty.
  In that case `AccessibilityTextReader` retries once after 200 ms, so a tap doesn't immediately say
  "No readable text".
- Spike R3 decides whether Chromium needs this at all.

---

## 5. Architecture

### 5.1 Core (`LargeTextCore`)

```
Sources/LargeTextCore/
  Models/
    HotkeyEvent.swift              HotkeyPhase, HotkeyEvent(phase, at)  — package vars + package init (convention, §4.1)
    PointerSample.swift            appKit point + derived global (top-left)
    ReadResult.swift               .text(ReadText) / .hidden / .nothing / .permissionMissing;
                                   ReadText(text, granularity, source, app, sourceFrame, TextWindow for native re-segmentation)
    ReadCandidates.swift           §4.3, plus TextSpan, TextWindow, ReadStep
    ReadGranularity.swift          requested unit: .sentence/.line/.paragraph
    ReadSource.swift               where the text came from: .selection/.unit/.element/.label/.walk/.ocr
    ReadPolicy.swift               Sendable per-session snapshot: denylist, elementTextLimit, maxCharacters
    ReaderContent.swift            .text(String, scrollToUTF16:) / .hidden / .nothing
    ReaderChrome.swift             fontSize, mode (.following/.pinned), appName, bundleID, sourceFrame
    ReaderIntent.swift             sessionID-tagged: .close(ReaderCloseReason), .zoom(ZoomStep)
  Ports/
    TextReading.swift              Sendable, not MainActor: read(at:granularity:pid:policy:) + pid-less extension (§4.4)
    PointerTracking.swift          @MainActor: current: PointerSample; startTicking(_:) -> token (60 Hz while following)
    KeyStateReading.swift          @MainActor: isPhysicallyDown(_ combo: KeyCombo) -> Bool?   (nil = unknown)
    ReaderPresenting.swift         @MainActor: §4.5 (present, update, pointerMoved, pin(content:chrome:), dismiss)
    HotkeyRegistering.swift        (changed) HotkeyEvent handler + registerPressOnly
    PreferencesStore.swift         (changed) readerHotkey, readerHoldThreshold, followingUnit, pinnedUnit, readerOCR
  Reading/
    ReaderGesture.swift            pure tap/hold machine on event timestamps; handle(_:) -> [ReaderEffect] (§3.1)
    ReadPlan.swift                 pure next-step decision (§4.3)
    ReadTextChooser.swift          pure ladder (§3.3)
    TextSegmenter.swift            pure unit-in-window + offset mapping + cap
    PointerThrottle.swift          pure re-read decision (§4.4)
    FallbackTextReader.swift       phase 2
    OCRLineMerger.swift            phase 2
  Session/
    ReaderDependencies.swift       textReader, pointer, keyState, presenter, notices, preferences, permissions, sleeper
    ReadingSessionCoordinator.swift executes ReaderEffects; synchronous hotkey(_:); one read in flight;
                                   (sessionID, seq) tags; isIdle; isClosing; idempotent close() that awaits the dismissal
  Fakes/
    StubTextReader.swift           per-point answers with an optional real delay — for the reader-stub scenario
    ScriptedPointer.swift          settable sample + manual tick
    FixedKeyState.swift            settable isPhysicallyDown
    LoggingReaderPresenter.swift   ReaderPresenting fake (logs only); default for AppEnvironment
```
`Notice` gains `.nothingToRead`, `.readerNeedsAccessibility`, `.readerMenuHint(KeyCombo)`.

**TestSupport** gains `ControllableTextReader`, which follows the `RecordingSleeper` pattern. It is
`@MainActor`, and therefore Sendable. Each `read` parks on a `CheckedContinuation` and records its
arguments; the test calls `complete(readIndex:with:)`. Every race in §6 is therefore deterministic, with
no real delays, under the existing `.timeLimit`.

### 5.2 Platform (`LargeTextPlatform`)

```
Sources/LargeTextPlatform/
  Reading/
    AccessibilityTextReader.swift  actor on its own serial queue: hit test → stage 0 → ReadPlan loop → chooser;
                                   early `.hidden` for denylisted pids; logging under the §4.10 rule
    WindowHitTester.swift          only if R4 requires it: CGWindowList → [WindowInfo]; pure candidate filter
    AXTextRangeReader.swift        native selection + text window + bounds (no support cache in v1)
    AXTextMarkerReader.swift       web units + selection via text markers
    AXElementWalker.swift          bounded child/ancestor walk with secure check on every node
    AXAttributes.swift             typed wrappers (string, CFRange, CGRect, parameterized)
    OCRTextReader.swift            phase 2
  Pointer/
    SystemPointerTracker.swift     PointerSample from NSEvent.mouseLocation (global derived); a @MainActor Task loop
                                   with Task.sleep(16 ms), only while ticking. The main queue is serviced in every
                                   common run-loop mode, so no Timer or `.common` registration is needed
  Keys/
    SystemKeyStateReader.swift     KeyStateReading: keyState, or the flagsState(.hidSystemState) modifier fallback (R1)
  Focus/
    AXAppPreparer.swift            scoped AXManualAccessibility + 200 ms retry hint (from AccessibilityFocusCapturer)
    AXConfiguration.swift          applyMessagingTimeoutIfNeeded(): the single home of the process-wide 0.1 s timeout
    AXGeometry.swift               (changed) + rect conversion for many displays; display-local rect for OCR
  Hotkey/
    CarbonHotkeyRegistrar.swift    (changed) pressed+released, GetEventKind routing, timestamp in callback, test seam
  Preferences/
    UserDefaultsPreferencesStore.swift  (changed) reader keys (conflicts are checked in Kit, §4.10)
```

### 5.3 UI (`LargeTextUI`)

```
Sources/LargeTextUI/
  Overlay/OverlayPanel.swift       (changed) allowsKey
  Reader/
    ReaderWindowController.swift   ReaderPresenting; following ↔ pinned without moving; fades; generation guard
    ReaderViewController.swift     backdrop + CardView + CardHeaderView + ReaderTextView + footer; scroll-to-index
    ReaderTextView.swift           read-only NSTextView; performKeyEquivalent → ReaderKeyBindings
    ReaderKeyBindings.swift        pure
    ReaderPlacement.swift          pure, with hysteresis (§4.6)
    HighlightPanel.swift           click-through outline
    ReaderStrings.swift
  Editor/CardHeaderView.swift      extracted from EditorViewController, shared
  Editor/CommandShortcutMatcher.swift  the whole ⌘-shortcut matcher, extracted from EditorKeyBindings, shared
  Theme/Theme.swift                (changed) followingMaxHeightFraction, highlight metrics
  Previews/ReaderPreviews.swift    label / long paragraph / following / pinned / "No text here" / "Hidden text"
  StatusItem/                      (changed) "Read Text Under Pointer" item; hotkeyUnavailable becomes [KeyCombo]
```

### 5.4 Kit (`LargeTextKit`)

- **`AppEnvironment`** gains `textReader`, `pointer`, `keyState` and **`readerPresenter`**. The name
  `reader` is kept for the coordinator in `AppController`. The new init parameters are appended with
  defaults, so the existing labelled call sites still compile. **The init becomes `@MainActor`**, because
  the defaults construct main-actor fakes. All callers already are main-actor: `live()`, `ScenarioTests`
  and `AppEnvironmentTests`. Defaults are `ScriptedPointer()`, `FixedKeyState()`, `StubTextReader()` and
  a new `LoggingReaderPresenter` in Core `Fakes/`.
  `AppEnvironmentTests.liveEnvironmentIsConstructibleWithoutSideEffects` asserts the new live types. `live()` builds `AccessibilityTextReader`,
  `SystemPointerTracker`, `SystemKeyStateReader` and `ReaderWindowController`; `readerDependencies()`
  assembles them.
- **`AppController`:**
  - creates the `ReadingSessionCoordinator`;
  - reader hotkey handler: `{ event in guard editor.isIdle else { return }; reader.hotkey(event) }`.
    This is synchronous; the coordinator starts its own tasks;
  - editor hotkey handler, status menu and present-on-launch all call `openEditorClosingReader()`, with
    its synchronous `editorOpenTask` guard (§4.8);
  - `HotkeyConflicts.validate` before registering the reader hotkey;
  - status-menu item → `.readerMenuHint`;
  - owns `ReaderProbe`, the 1 s driver of the `reader-probe` scenario. The coordinator knows nothing
    about it.
- **`Scenario`:**
  - `reader-stub`: `StubTextReader` answers by pointer x (short label / long paragraph / nothing / hidden),
    with a configurable delay so races can be tried by hand;
  - `reader-no-accessibility`;
  - `reader-probe`: the live reader **logs every stage-0 attribute name and the supported parameterized attributes** for the
    element under the pointer once per second. It logs lengths only, under the §4.10 rule. This is the
    harness for spikes R2–R6 and R8.
- **`LaunchConfiguration`:**
  - `--present-reader-on-launch=pinned|following|nothing|hidden|long` implies the `reader-stub` reader.
    The live reader has no "stub text".
    - `following` drives the coordinator with a scripted press and no release, plus the live pointer.
      Placement and hysteresis can then be watched without holding four keys. It swaps in
      `FixedKeyState(isDown: true)`, so the key-state check doesn't see "released", and suppresses the
      30 s cap.
  - `--reader-hold-threshold <ms>` and `--following-unit <sentence|line|paragraph>` override the
    preferences, so the tunables can be tried without a settings UI. They are applied as an **in-memory
    overlay** on top of the store and never written to the real `UserDefaults`, the same way scenarios
    swap in `InMemoryPreferencesStore`.

### 5.5 Data flow: hold to read

```
Carbon key-down (stamped) ─▶ AppController ─▶ reader.hotkey(.pressed @t0)       [sync, main actor]
   ReaderGesture: idle → following(t0) → [startFollowing]; policy = ReadPolicy(prefs); seq = 1;
   Task { await textReader.read(at: pointer.current, granularity: .sentence, policy: policy) }
   pointer.startTicking { sample in coordinator.pointerMoved(sample) }
       → presenter.pointerMoved(sample) (placement) · pendingPoint · keyState check
read #1 returns (on main actor) ─▶ still following & seq current? ─▶ presenter.present(.following, …)
   pendingPoint passes PointerThrottle? ─▶ read #2 …                          (one in flight)
Carbon key-up (stamped t1, t1 − t0 ≥ 300 ms) ─▶ ReaderGesture → closing
   stop ticking; in-flight result will be dropped; await presenter.dismiss() → idle
```
**Tap** (t1 − t0 < 300 ms):
- `ReaderGesture` moves to pinned and ticking stops.
- If a card is shown: re-segment it to the pinned unit, then `presenter.pin(content:chrome:)`.
- If read #1 is still running: present the card pinned when it arrives.

---

## 6. Testing strategy

The existing pattern stays: Swift Testing, pure functions tested directly, coordinators tested with
`Fakes/` and `LargeTextTestSupport` spies.

| Suite | Covers |
|---|---|
| `ReaderGestureTests` | effects output (`startFollowing`/`pin`/`close`/`ignore`); `.forceClose` only after a decided hold; press during closing and its release ignored; tap, hold and the threshold edge, all from **event timestamps**; press while following handled per the R1 outcome (missed release, or ignored); a poll-created release before `holdThreshold + 100 ms` is impossible (a tap released at 280 ms is never a hold); press while pinned closes and the next release is ignored; a lone release is ignored; max follow duration |
| `ReadingSessionCoordinatorTests` | **Races**, using `ControllableTextReader` (no real delays): release (tap) before read #1 finishes → presented pinned; release (hold) before read #1 → nothing presented; a move while a read runs → one follow-up read with the latest point; pin while a read runs → frozen on the last displayed result; a stale `seq` is dropped; a result after close is dropped. **Also:** deduplication, zoom persisting the shared font size, stale-session intents ignored, `.nothing` on tap → HUD, `.hidden` on tap → pinned card, `.permissionMissing` mid-follow → close + one HUD, a result after pin dropped, `pointerMoved` forwarded on every tick, the `ReadPolicy` snapshot passed to every read, `isIdle`. **`close()` twice during a fade awaits the same dismissal; two editor presses during the reader fade open the editor exactly once; a second press arriving before the first Task has started is ignored** (Kit test with spies); tap before read #1 → `pinnedAwaitingFirst` → presented pinned on arrival; every phase change comes from a `ReaderEffect` |
| `ReadPlanTests` | step order per role and attribute combination; short native static text → `.value` → `.done`; **an `AXTextArea` with 1 M characters never emits `.value`**; **short static text in a web area → `.textMarkers`**; **an unsupported or failed step → never repeated, ends in `.done`** |
| `ReadTextChooserTests` | the §3.3 ladder; secure **subrole**; hidden found during a walk; denylisted app (defence in depth; the actor's early `.hidden` is covered by a Platform test with a stubbed pid lookup); web selection vs. native selection; a long `value` is not used as element text; label order |
| `TextSegmenterTests` | units inside a window with offset mapping; window edges; CRLF; emoji and UTF-16 offsets; the cap |
| `PointerThrottleTests` | interval, distance, leaving the frame |
| `FallbackTextReaderTests`, `OCRLineMergerTests` | phase 2 |
| `WindowHitTesterTests` (only if R4 requires the fallback) | our own pid skipped; alpha 0; front-to-back order; transparent overlay windows from other apps (HazeOver-like, layer > 0); WindowServer and Dock owners; the 3-candidate cap |
| `AXGeometryTests` | the conversion both ways; a secondary display left of and above the primary with a different height; edge pixels; the display-local OCR rect |
| `CarbonHotkeyRegistrarTests` | routing pressed vs. released through the internal `handle(hotKeyID:kind:time:)` seam with `insertHandlerForTesting` |
| `HotkeyConflictsTests`, `StatusMenuModelTests` | an equal combo skips the reader; several unavailable combos listed |
| `LaunchConfigurationTests` | `--present-reader-on-launch=…` values, `--reader-hold-threshold`, `--following-unit` |
| `UserDefaultsPreferencesStoreTests` | the reader keys |
| `ReaderPlacementTests` | opposite half; hysteresis (crossing the middle doesn't flip, entering the card does, **with no new result**); tall source; small screen; many displays; pin keeps the anchor edge and grows to the pinned cap; direct pin centres |
| `ReaderKeyBindingsTests`, `CommandShortcutMatcherTests` | including ⌘C and ⌘A on non-US layouts; the existing `EditorKeyBindingsTests` still pass unchanged |
| `ReaderWindowControllerSmokeTests` | present following → not key, `ignoresMouseEvents`, panel sized to the card; pin → `allowsKey`, panel sized to the screen; dismiss |
| `AppEnvironmentTests`, `ScenarioTests` | the new services and scenarios |

**Manual checklist** (`docs/manual-testing.md`):
- clicks actually pass through while following;
- the card never steals focus from the target app while following;
- both gestures over full-screen video and across displays;
- the R2 app matrix;
- observe and record how the panels appear in a screen recording and screen share (evidence for the
  deferred `readerHideFromScreenSharing`);
- the editor shortcut while the reader is open.

---

## 7. Spikes

| # | Question | Decides | When |
|---|---|---|---|
| R1 | Is `kEventHotKeyReleased` reliable when a modifier is released first? Does Carbon send auto-repeat presses? Does `CGEventSource.keyState(.combinedSessionState, …)` return real values **without Input Monitoring**? Is `GetEventTime(event)` the real keystroke time? Test: block the main thread for about 500 ms, tap, and compare it with `GetCurrentEventTime()` inside the callback. Also log `NSApp.currentEvent?.timestamp` (the window server's HID time base), the fallback if `GetEventTime` is stamped at dequeue. | `KeyStateReading` mode: `keyState`, or the `flagsState` modifier fallback; how auto-repeat is filtered; which timestamp to trust | **M0** |
| R4 | Does the system-wide AX hit test skip an `ignoresMouseEvents` panel, both the card **and a highlight outline lying under the pointer**? | Whether `WindowHitTester` is built at all; single-panel vs. four-edge highlight | **M0** |
| R6 | Cost of a stage-0 read and of a text-window read on a dedicated serial executor; **for comparison, a `value` read of a 1 MB `AXTextArea`**; cost of `CopyParameterizedAttributeNames`; behaviour with a hung app; does the 0.1 s timeout hold? | Budgets; whether per-pid back-off and a support cache are needed; confirms the threading decision before the ports freeze | **M0** |
| R2 | Matrix: Safari, Chrome, Arc, Firefox, Mail, Notes, Pages, Preview (PDF), Finder (list/icon), System Settings, Xcode, Terminal, iTerm2, VS Code, Slack, menu bar (including app menus), Dock, Notification Center, **open menus being tracked in another app, Mission Control, Stage Manager strips, the lock/login screen** (should be nothing). Which ladder step, how many calls, how long? **Also note hover side effects of holding ⌃⌥⌘** (Xcode ⌘-hover links, ⌥ in Finder) and the clash with macOS Hover Text, which uses ⌘ by default. | Default units; web scope in v1 | M2 |
| R3 | Chromium browsers: are hit testing and text markers available, with or without `AXManualAccessibility`, and never `AXEnhancedUserInterface`? | Chromium support | M4 |
| R5 | Text markers in WebKit, Chromium, **Gecko (Firefox)** and Electron, including `AXSelectedTextMarkerRange` | Scope of `AXTextMarkerReader` | M4 |
| R7 | OCR: `SCShareableContent` cost; capture and Vision latency with the app-excluding filter; re-confirmation prompts | Automatic vs. explicit OCR | M6 |
| R8 | Terminal and iTerm2: `RangeForPosition` and `StringForRange` windows in scrollback | Window size | M3 |

---

## 8. Milestones

0. **M0: Probe and decide.**
   - Build the `reader-probe` scenario (with `ReaderProbe` in Kit) on a minimal `AccessibilityTextReader`
     (hit test + stage 0, on its serial executor).
   - Add `HotkeyEvent` with key-up, updating the four broken call sites (§4.1) in the same change.
   - Add `AXConfiguration.applyMessagingTimeoutIfNeeded()`.
   - Run R1, R4 and R6.

   *Exit:* the `TextReading`, `HotkeyRegistering`, `PointerTracking` and `KeyStateReading` signatures are
   frozen. R4 decides whether `WindowHitTester` exists; R6 decides whether back-off and a cache exist.
1. **M1: Plumbing.**
   - `ReaderGesture` and `ReadingSessionCoordinator` (with all race tests) using `ControllableTextReader`;
   - `OverlayPanel.allowsKey`, `ReaderWindowController`, and a **basic `ReaderPlacement` with
     hysteresis**;
   - `CommandShortcutMatcher` extracted, plus `ReaderKeyBindings`, both needed by the pinned card;
   - the `reader-stub` scenario, `--present-reader-on-launch=…`, the tunables' launch arguments, and the
     editor/reader interplay, including the idempotent `close()`.

   *Demo:* hold and tap with fake text, including deliberately slow reads.
2. **M2: AX basics.**
   - `ReadPlan`, `ReadTextChooser`, label, value and walk;
   - hidden-content rules (secure subrole, hard-coded denylist checked before stage 0), the permission
     HUD, the logging rule;
   - the R2 matrix.

   *Demo:* read buttons, menu items and labels anywhere.
3. **M3: Text units.**
   - native selection and text window, `TextSegmenter`, re-segmentation on pin;
   - scroll-to-index on overflow, `HighlightPanel`, `PointerThrottle`;
   - R8.

   *Demo:* hover paragraphs in Notes, Mail, Xcode and Terminal.
4. **M4: Web.** `AXTextMarkerReader` (the sentence stays on pin; Gecko fallback), Chromium detection,
   scoped `AXManualAccessibility` (R3, R5).
5. **M5: Polish.** Preferences, status-menu hint and the hotkey-conflict list, shared `CardHeaderView`
   previews, manual checklist.
6. **M6 (phase 2): OCR.** ScreenCaptureKit + Vision, `FallbackTextReader`, Screen Recording permission UI
   (R7).

---

## 9. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Tap seen as hold because of slow reads | Event timestamps taken in the Carbon callback; synchronous gesture handling; reads off the main actor |
| Main-thread jank while following | Dedicated serial AX executor; one read in flight; staged extraction with no `value` in stage 0; per-pid back-off if R6 shows it is needed |
| Wrong window hit (click-through overlays from other apps) | System-wide hit test (follows mouse routing); a capped `CGWindowList` fallback only if R4 requires it |
| Poor AX text in some apps (canvas, games, some Electron) | Label and walk ladder; OCR in phase 2; R2 matrix from the probe logs |
| Card covers the pointed-at content or jumps around | Opposite-half placement with hysteresis evaluated on every pointer tick; click-through; no jump on pin; highlight outline |
| Carbon release lost or key appears stuck | Per R1: press-while-following = missed release, or presses ignored; `KeyStateReading` check on the pointer tick after the hold threshold (`keyState`, or the `flagsState` modifier fallback); 30 s cap |
| Secrets shown huge to the room or in a screen share | Secure subrole check on every visited element; password-manager denylist checked before any string is fetched; content never logged; OCR images kept in memory only. (`sharingType = .none` is not relied on; §4.10) |
| Turning on other apps' AX trees costs them CPU and memory | Scoped to the pid being read, only after an empty result; logged |
| Undocumented web text markers change | Isolated in one file; falls back to element text |
| Coordinate mistakes across displays | One `PointerSample`; conversion exactly once at the Platform boundary; multi-display geometry tests |

---

## 10. Open product questions (after hands-on)

1. Units: are sentence (following) and paragraph (pinned) right, or should a second tap expand line →
   paragraph → whole element?
2. Is following without a backdrop readable enough over busy content?
3. Should the reader share the editor's font size (current plan) or have its own?
4. Is 300 ms the right hold threshold from the couch?
5. **Speak it** (`AVSpeechSynthesizer`, one key when pinned)?
6. **Keyboard-focus mode:** reading the focused element's selection or caret line when the pointer is
   idle or hidden, or when invoked from the status menu. Deferred: it needs its own fallbacks and tests.
7. Should OCR run automatically, or only on an explicit modifier variant?
8. Which apps go on the default denylist?

---

## 11. Revision log

### Draft 1 → draft 2 (independent review)

1. **Tap/hold race and ordering.** Timestamps are now taken in the Carbon callback (`HotkeyEvent`).
   `hotkey(_:)` is synchronous and reads are child tasks. Release-before-first-read is now specified (tap
   → present pinned, hold → nothing), with tests (§3.1, §5.5, §6).
2. **"Async isn't off-main" under `NonisolatedNonsendingByDefault`.** The AX reader is now an actor on a
   dedicated `DispatchSerialQueue` executor, and `TextReading` is a `Sendable`, non-`MainActor` port.
   `AXUIElement` never crosses the boundary (§4.4).
3. **`CGWindowList` hit testing is fooled by overlay windows.** The system-wide hit test comes first;
   `CGWindowList` is a fallback capped at 3 pids, with overlay and system-owner tests (§4.2).
4. **Too many AX calls per read.** Extraction is staged: a stage-0 batch, then `ReadPlan` (Core) picks
   further steps. The first `cannotComplete` aborts the read with immediate back-off. Child reads are
   bounded (§4.3).
5. **Full-text fetch.** Replaced by a ±2 000-unit `TextWindow` via `StringForRange`.
   `fullTextFetchLimit` is gone (§4.3).
6. **Stale or concurrent reads.** One read in flight, newest point wins, `(sessionID, seq)` tags, frozen
   on the last *displayed* result at pin, with race tests (§4.4, §6).
7. **Coordinates.** A single `PointerSample` with both systems; conversion once at the Platform
   boundary; multi-display and display-local OCR tests. The new `resolve(point:)` overload was dropped in
   favour of the existing `ScreenResolver` API (§4.2, §4.6, §4.9).
8. **Secure subrole; walks; web selection.** Hidden content is detected by subrole via
   `ElementKind.classify` on every visited node. Web selection uses `AXSelectedTextMarkerRange` (§3.3,
   §4.3).
9. **Following-mode overflow.** Sentence while following, paragraph when pinned (re-segmented with no
   extra read), and scroll-to-index on overflow (§3.2, §4.3).
10. **Card jumps.** Placement hysteresis; pin keeps the frame; `orderFrontRegardless` while following
    (§4.5, §4.6).
11. **Release fallback and port details.** Input Monitoring added to R1; `@MainActor` kept; routing by
    `GetEventKind`; 30 s cap; press-while-following = missed release; press-only convenience overload
    (§3.1, §4.1).
12. **AX activation costs and browsers.** `AXManualAccessibility` scoped to the pid being read after an
    empty result, Chromium detected by bundle ID, Firefox put back in scope for R5 (§4.11, §7).
13. **Privacy.** Password-manager denylist, explicit logging rule, `sharingType = .none`, OCR images in
    memory only (§4.10).
14. **OCR details.** Cached `SCShareableContent`; display-local `sourceRect` (§4.9). In draft 3, the
    content-filter overload is always used.
15. **`FeatureArbiter` removed.** Replaced by `isIdle` and `close()` on the coordinators (§4.8).
16. **Keyboard-focus mode deferred.** The menu item shows a hint HUD instead (§4.10, §10).
17. **Panel reuse.** `OverlayPanel.allowsKey` instead of a new panel class; ⌘C and ⌘A routed through
    `performKeyEquivalent` (§4.5).
18. **Pointer tracking.** A 60 Hz poll while following instead of event monitors (§2, §5.2).
19. **R2 gaps and duplicate combos.** More R2 cases; preferences refuse a reader combo equal to the
    editor's (§3.1, §7).
20. **Ordering.** A new M0 (probe + R1/R4/R6) runs before the ports freeze; placement moved to M1;
    click-through and focus checks moved to the manual checklist (§6, §8).

### Draft 2 → draft 3 (the reviewer's follow-up check)

The follow-up check found 15 of 20 findings addressed and 5 partly addressed, plus 11 new issues
(N1–N11). The changes:

- **N1, timeout only set lazily.** It is now set once in `AppController.start()` and when trust is first
  granted. The two `AXAppPreparer` instances are deliberate and documented (§4.4, §4.11).
- **N2, `sharingType` overpromised.** It is now opt-in (`readerHideFromScreenSharing`, default off) and
  described as best effort. The checklist observes the behaviour instead of asserting it (§4.5, §4.10,
  §6, §9).
- **N3, main-thread-skewed stamps.** Stamps now use `GetEventTime(event)`, with the 30 s cap on the same
  time base (§3.1, §4.1).
- **N4, full-screen panel while following.** The panel is card-sized while following and full-screen
  only when pinned (§4.5).
- **N5, OCR can see our own windows.** The content-filter overload, which excludes our app, is always
  used (§2, §4.9, §7).
- **N6, web re-segmentation.** One paragraph read on pin for the web path (§4.3).
- **N7, pin geometry.** Origin and anchor edge are kept, the card grows to the pinned cap, and a direct
  pin is centred (§3.2, §4.6, §6).
- **N8, overload ambiguity.** Renamed to `registerPressOnly`, with `package` access, and the editor call
  site is updated explicitly (§4.1).
- **N9, timer in menu tracking.** The timer runs in `.common` run-loop modes (§5.2).
- **N10, hung read blocks the next session.** The worst case (about 0.1–0.2 s) is stated and checked by
  R6 (§4.4).
- **N11, auto-repeat filter.** No interval filter: R1 decides between "press = missed release" and
  "ignore all presses while following" (§3.1).
- **Finding 12, part 2: empty tree right after enabling.** One retry after 200 ms (§4.11).

### Draft 3 → draft 4 (final check by a fresh reviewer)

The final check marked N1–N11 and findings 12–14 as handled and judged the plan **ready for M0**. It
raised six small follow-ups, now fixed:

1. **The `keyState` poll could turn a tap into a hold.** The poll now starts only after
   `holdThreshold + 100 ms`, and only Carbon's own release decides tap vs. hold. Covered by a test
   (§3.1, §6).
2. **The highlight lies under the pointer.** It is now part of R4, with a four-edge-window fallback. §2
   no longer states R4's open question as fact (§2, §4.7, §7).
3. **The web paragraph read on pin would be dropped by the stale-read rule.** It is now tagged
   `pinSeq`, accepted while pinned, and sent straight to the frozen pid. The `markerUnits` wording in
   §5.1 is corrected (§4.3, §5.1).
4. **`GetEventTime` may itself be late.** A blocked-main-thread comparison test is added to R1 (§7).
5. **The timeout had two homes.** The single home is now `AXConfiguration.applyMessagingTimeout()`,
   called from `AppController` (§4.4, §5.2).
6. **Leftovers.** "Per R1" wording in the diagram, tests and risks; read cancellation and
   `Task.isCancelled` around the 200 ms retry, with the worst case updated to about 0.4 s; the full
   `ScreenResolver.resolve` signature.

### Draft 4 → draft 5 (fresh review checked against the existing code)

The reviewer verified the plan against `packages/LargeTextPackage`. Most of the reused types exist with
the assumed shapes, and `ApproachableConcurrency` is enabled. It found **2 Critical** issues, all fixed:

- **C1, stage 0 fetched `value`.** That reintroduced full-text fetches of megabyte documents on every
  following read. Stage 0 no longer reads `value`; the new `ReadStep.value` runs only for short elements.
  R6 compares the cost (§2, §3.3, §4.3, §6, §7).
- **C2, the `ReadPlan` contract.** It had no web signal, could loop forever, and keyed the support cache
  wrongly. `ReadCandidates` gains `supportedParameterized`, `webArea` and `attemptedSteps`. `ReadPlan`
  never repeats a step. The cache is dropped until R6 shows a need (§4.3, §6).

Important:
- **I1, compile and linking.** `TextReading` has no default argument; the pid-less form is a protocol
  extension. All new models use `package var` + `package init`. The four broken call sites are listed for
  M0, and the new `AppEnvironment` parameters get defaults. `AppEnvironment.reader` is renamed
  `readerPresenter` (§4.1, §4.4, §5.4).
- **I2, gesture timing ports.** `KeyStateReading` port; the check runs on the pointer tick; `.forceClose`
  carries no timestamp; the delay and the cap use `Sleeper` (§3.1, §5.1).
- **I3, gated `keyState`.** `flagsState` modifier fallback (§3.1, §7 R1).
- **I4, editor/reader race.** `close()` is idempotent and awaits the dismissal; the editor hotkey is
  ignored while the reader is closing; there is a single `openEditorClosingReader()` path; tested (§4.8,
  §5.4, §6).
- **I5, denylist too late and off-main.** A Sendable `ReadPolicy` is snapshotted per session; the actor
  returns `.hidden` before stage 0 (§3.3).
- **I6, unspecified transitions.** `ReaderGesture.handle -> [ReaderEffect]` is the single source of truth.
  A transition table covers press during closing, `.nothing` and `.hidden` at pin, a permission lost
  mid-follow, and late results after pin (§3.1, §6).
- **I7, hysteresis input.** `ReaderPresenting.pointerMoved(_:)` on every tick (§4.5, §4.6).
- **I8, timeout "when trust is granted".** `applyMessagingTimeoutIfNeeded()` with an
  `OSAllocatedUnfairLock`, called idempotently from launch, `read` and `captureFocus` (§4.4).
- **I9, delay-based race tests.** `ControllableTextReader` in TestSupport (§5.1, §6).
- **I10, scope.** These now wait for spike results or hands-on: `WindowHitTester` (R4), back-off and the
  support cache (R6), the web `pinSeq` paragraph read (hands-on), `readerHideFromScreenSharing`, and the
  editable denylist. The hard-coded denylist stays.
- **I11, controlled launch states.** `--present-reader-on-launch=pinned|following|nothing|hidden|long`,
  the tunables' launch arguments, and `ReaderProbe` owned by Kit (§5.4).

Nice-to-haves applied:
- the pointer tracker uses a `Task` loop, and `PointerSample` is derived from one `NSEvent` sample;
- R1 also logs `NSApp.currentEvent?.timestamp`;
- the Carbon test seam;
- `CommandShortcutMatcher` instead of `ZoomKeyMatcher`;
- `pin(content:chrome:)` and `ReaderContent`;
- `ReadUnit` split into `ReadGranularity` and `ReadSource`;
- hotkey conflicts checked in Kit, and the status menu lists several unavailable combos;
- the back-off exemption after `AXManualAccessibility`;
- the Gecko fallback;
- OCR coordinate and scale details;
- `sharingType` removed from the mitigations;
- hover side effects added to R2.

### Draft 5 follow-up (the same reviewer's check: "agree with conditions")

All six conditions and three minor items have been applied:
1. **Editor/reader race window.** A synchronous `editorOpenTask` guard in `AppController` replaces the
   `isClosing` check, which missed a second press arriving before the first Task started. Tested (§4.8,
   §5.4, §6).
2. **`ReaderGesture` owns every phase change.** `.forceClose(reason)` is valid in any non-idle phase;
   `.dismissed` and `.firstResultArrived` inputs are added; there is a `pinnedAwaitingFirst` phase; the
   "pinned | dropped" row no longer contradicts the tap rule; the poll guarantee now comes from when the
   check starts (§3.1).
3. **Sleeper fake:** `RecordingSleeper.heldDurations: Set<Duration>` with `release(_:)` (§3.1).
4. **`AppEnvironment.init` is `@MainActor`,** plus a `LoggingReaderPresenter` fake and live-type
   assertions (§5.1, §5.4).
5. **The `following` launch state** uses `FixedKeyState(isDown: true)` and suppresses the cap (§5.4).
6. **Stale lines fixed:** §2 pointer rows, §3.1 conflict wording, §3.3 policy source.

Minor:
- an own-pid hit while following is "no update" (§4.2);
- tunable overrides are an in-memory overlay (§5.4);
- `CommandShortcutMatcher` moved to M1 (§8).

### Implementation follow-up

- **C3, control values hid their names.** Dictop's selected SwiftUI Soniox button showed only
  "Selected" (or "Multiple languages") because the short-value rung preceded its description. Core now
  shows a control's name followed by its distinct short value, while text-value roles keep value first.
  The read plan still tries a labelled control's value once and excludes non-text values (§3.3).
