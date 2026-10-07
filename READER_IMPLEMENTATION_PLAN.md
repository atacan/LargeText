# LargeText Reader — Technical Implementation Plan (draft 4)

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
> Draft 2 includes an independent review. Draft 3 includes that reviewer's follow-up check, and draft 4 a fresh reviewer's final check. See §11.

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
| Pointer location | Yes | `NSEvent.mouseLocation` (AppKit, bottom-left) and `CGEvent(source: nil)?.location` (global, top-left), sampled together by Platform | None |
| Pointer movement while following | Yes | A 60 Hz timer polling the location only while following. This also catches drags, which a `.mouseMoved` monitor misses | None |
| AX element under the pointer | Yes | `AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), x, y, &el)` is *expected* to follow the window server's mouse routing and skip click-through windows (R4 confirms). `AXUIElementGetPid` then gives the owner | Accessibility |
| Fallback when the system-wide hit lands on us or fails | Yes | `CGWindowListCopyWindowInfo(.optionOnScreenOnly, …)` provides pid candidates, front to back, then an app-scoped `AXUIElementCopyElementAtPosition` per candidate. Window *names* need Screen Recording; we never read them | None / Accessibility |
| Text of a label, button or static text | Yes | One batched `AXUIElementCopyMultipleAttributeValues` read of role, subrole, value, title, description, help, placeholder, number of characters, position and size | Accessibility |
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
`PreferencesStore.readerHotkey`. Preferences refuse a combo that equals the editor's; the second
registration reports `hotkeyUnavailable`.

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
- Every reader duration uses the same time base (`GetCurrentEventTime()`), including the 30 s cap.
  `ContinuousClock` is not used for these.
- `ReaderGesture` is a pure state machine. It compares those timestamps, so a slow read or a busy main
  actor can't turn a tap into a hold.

**Auto-repeat:** R1 decides.
- If Carbon sends **no** auto-repeat presses, a `pressed` arriving while *following* is treated as a
  missed release, and the reader closes.
- If it **does**, every `pressed` while following is ignored. Lost releases are then caught only by the
  `keyState` poll or the 30 s cap.

A time-interval filter is not used, because it can't tell a repeat from a deliberate fast double-press.

**Stuck-key protection:**
- While following, a 50 ms safety poll asks `CGEventSource.keyState(.combinedSessionState, key:)` whether
  the key is up. This depends on spike R1 confirming that the call works without Input Monitoring; if it
  is gated, the poll is dropped.
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
2. **Selection under the pointer:**
   - native: `kAXSelectedTextRangeAttribute` plus `kAXBoundsForRange…` to check the pointer is inside;
   - web: `AXSelectedTextMarkerRange` on the `AXWebArea` plus `AXBoundsForTextMarkerRange`.
3. **Unit at the pointer:** a sentence (following) or a paragraph (pinned), taken from a text window
   around the pointer index (native) or from text markers (web).
4. **Whole element text, when short:** `value` ≤ `elementTextLimit` (500 characters). Examples are
   static text, a cell, or a text field's value.
5. **Label:** title, then description, then help, then placeholder. This covers buttons, menu items,
   toolbar icons, tabs and Dock items.
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
package struct HotkeyEvent: Sendable { let phase: HotkeyPhase; let at: TimeInterval }

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
- `SpyHotkeys` gains `simulate(_ phase:, at:)`;
- the editor's call site in `AppController` is changed explicitly to `registerPressOnly`.

A modifier-only hold (e.g. holding right ⌥) would need a `CGEventTap` with Input Monitoring. It is not in
v1.

### 4.2 Hit testing

1. **Sample the pointer once, in Platform**, as a `PointerSample`:
   - `global`: top-left coordinates for CG and AX, from `CGEvent(source: nil)?.location`;
   - `appKit`: from `NSEvent.mouseLocation`.

   From there on, AX/CG code only uses `global`, and UI code only uses `appKit`.
2. **System-wide hit test first:**
   `AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), global.x, global.y, &el)`, then read
   the owner with `AXUIElementGetPid`. If the pid isn't ours, use the element.
3. **Fallback:** the hit returned our own pid (our card or highlight) or failed.
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
    var value: String?, title: String?, description: String?, help: String?, placeholder: String?
    var characterCount: Int?
    var elementFrame: CGRect?
    var selection: TextSpan?          // set only if the pointer is inside it
    var window: TextWindow?           // text around the pointer + offsets
    var markerUnits: [ReadUnit: TextSpan]  // web path: unit → text + bounds
    var childTexts: [String]
    var ancestorLabel: String?
    var hiddenEncountered: Bool       // a secure element was seen in the walks
}
package struct TextWindow: Sendable, Equatable {
    var text: String                  // ≈ index ± 2 000 UTF-16 units, clamped to characterCount
    var start: Int                    // UTF-16 offset of `text` in the element
    var indexAtPointer: Int           // UTF-16 offset in the element
}
package enum ReadStep: Sendable { case selection, textWindow, textMarkers, walk, done }
```

- **Stage 0** (always): one `AXUIElementCopyMultipleAttributeValues` batch with role, subrole, value,
  title, description, help, placeholder, `kAXNumberOfCharactersAttribute`, position and size. This is the
  same `AXBatchResult` helper the focus capturer uses.
- **Then** the pure `ReadPlan.next(after: candidates, unit:) -> ReadStep` (Core) names the next expensive
  step, or `.done`. Examples:
  - a short `AXStaticText` value → `.done`;
  - an `AXTextArea` with many characters → `.selection`, then `.textWindow`;
  - an element inside an `AXWebArea` → `.textMarkers`;
  - an empty `AXGroup` → `.walk`.
- Platform runs that step, merges the result into `ReadCandidates` and asks again.
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
- **Web:** marker ranges can't be re-segmented locally. On pin, the coordinator issues **one** extra read
  for the paragraph at the frozen point.
  - The call is `read(at:unit: .paragraph, pid: frozenPid)`. Passing the pid of the last displayed result
    makes the hit test go straight to that app. By then the panel is full-screen and clickable, so a
    system-wide hit test would land on our own backdrop.
  - The read is tagged `(sessionID, pinSeq)`. It is the **one result accepted while *pinned***, and only
    if `pinSeq` matches. Every other in-flight read is still dropped at pin (§4.4).
  - Until it returns, the sentence stays displayed. If it fails, the sentence stays.

  Fetching both units on every following read was rejected: it adds two calls to every read for a
  benefit seen only at pin time.

**Web path:** `AXTextMarkerReader` walks up to the `AXWebArea`. It then runs
`AXTextMarkerForPosition` → `AX{Sentence,Paragraph,Line}TextMarkerRangeForTextMarker` →
`AXStringForTextMarkerRange` and `AXBoundsForTextMarkerRange`, plus `AXSelectedTextMarkerRange` for the
selection. It lives in its own file because these attributes are undocumented.

**Parameterized-attribute support** is checked with `AXUIElementCopyParameterizedAttributeNames`, cached
per `(pid, role)`. Unsupported steps are skipped instead of timing out.

**Error policy:**
- The first `kAXErrorCannotComplete` aborts the whole read and starts the per-pid back-off **at once**
  (skip that pid for 1 s).
- `kAXErrorAttributeUnsupported` and `kAXErrorNoValue` just leave the field `nil`.

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
    package func read(at pointer: PointerSample, unit: ReadUnit) async -> ReadResult
}
```

`TextReading` is a `Sendable` protocol that is **not** `@MainActor`. Blocking AX calls sit on that one
dedicated thread, not on the cooperative pool and not on the main thread.

**Messaging timeout:**
- The 0.1 s AX messaging timeout is process-wide. Today it is set lazily, and only by the focus capturer.
  If the reader ran first, the default timeout (about 6 s) would apply, and one hung app would stall the
  serial queue for seconds.
- So the timeout gets one home: a Platform function, `AXConfiguration.applyMessagingTimeout()`, which
  calls `AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.1)`.
  - `AppController.start()` calls it at launch, and again when trust is first granted.
  - `AXAppPreparer` does **not** set it.
- The lazy call in the focus capturer is removed.

**Worst case:** a read can't be cancelled in the middle of an AX call. After release, a read still
running against a slow app can delay the next session's first read by about 0.1–0.2 s. This is bounded
by the timeout, abort-on-`cannotComplete` and the back-off, and R6 checks it.

**Cancellation and the 200 ms retry:**
- The coordinator **cancels** the read `Task` when the session ends or the reader pins.
- The reader checks `Task.isCancelled` before each stage and after the 200 ms retry sleep (§4.11), so a
  cancelled read gives up between AX calls.
- The retry sleep suspends the actor, so other reads may run in between. That is fine: each result is
  still checked against its `seq`.
- With the retry, the worst case for a first read is about 0.4 s.

**The coordinator issues reads:**
- **One read in flight.** Pointer ticks while a read runs only replace `pendingPoint`. When the read
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
  - ⌘= / ⌘+ / ⌘- / ⌘0 → zoom. The zoom matching is extracted from `EditorKeyBindings` into a shared
    helper.
  - ⌘C / ⌘A → direct `copy(nil)` / `selectAll(nil)` from `ReaderTextView.performKeyEquivalent`. This is
    needed because the package never installs `NSApp.mainMenu`, the same reason `LargeTextView` does it.
- Fades respect Reduce Motion. Text updates while following are not animated.

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
  24 pt margin, never just because it crossed the middle of the screen.
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

### 4.9 OCR fallback (phase 2, opt-in)

- Runs only when the AX reader finds nothing, **or** on an explicit variant (⇧ added to the shortcut),
  **and** only if `preferences.readerOCR == true`.
- **Capture:** a band around the pointer, using the element frame if there is one, else 900 × 240 pt.
  - Always `captureImage(contentFilter:configuration:)`, with a filter that **excludes our app**, so our
    own card and highlight are never recognised. `captureImage(in:)` (15.2+) has no filter and isn't used.
  - Cached `SCShareableContent`, refreshed on `NSApplication.didChangeScreenParametersNotification`.
  - `sourceRect` is **display-local**: the global rect minus the `SCDisplay` frame. Tested in
    `AXGeometryTests`.
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
    Stored in `readerDenylist`, editable with `defaults`.
- **Logging rule:** log role, subrole, ladder step, text *lengths*, durations, AX error codes and bundle
  ID. Never log any AX string attribute (value, title, description, help, placeholder, selection), even
  at debug level.
- **Screen-sharing exclusion is opt-in and best effort.**
  - The preference `readerHideFromScreenSharing` defaults to off. Sharing on purpose (remote help,
    showing a family member over FaceTime) is a real couch use case.
  - When on, the panels get `sharingType = .none`. That is only a hint: ScreenCaptureKit's handling has
    changed between macOS releases, so the plan doesn't promise it.
- **Accessibility missing:** HUD "Allow Accessibility to read text" plus the existing "Grant Access…"
  status-menu item.
- `Permissions.screenRecording` is added in phase 2.
- **Status menu:** "Read Text Under Pointer (⌃⌥⌘R)" shows the HUD "Point at text and press ⌃⌥⌘R". The
  pointer is on the menu at that moment, so reading would be pointless. A keyboard-focus reading mode is
  deferred (§10).

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
    HotkeyEvent.swift              HotkeyPhase, HotkeyEvent(phase, at)
    PointerSample.swift            global (top-left) + appKit points
    ReadResult.swift               .text(ReadText) / .hidden / .nothing / .permissionMissing;
                                   ReadText(text, unit, app, sourceFrame, TextWindow for native re-segmentation; markerUnits for display only)
    ReadCandidates.swift           §4.3, plus TextSpan, TextWindow, ReadStep
    ReadUnit.swift                 .selection/.sentence/.line/.paragraph/.element/.label/.ocr
    ReaderChrome.swift             fontSize, mode (.following/.pinned), appName, bundleID, sourceFrame, pointer
    ReaderIntent.swift             sessionID-tagged: .close(ReaderCloseReason), .zoom(ZoomStep)
  Ports/
    TextReading.swift              Sendable, not MainActor: read(at: PointerSample, unit:, pid: Int32? = nil) async -> ReadResult
    PointerTracking.swift          @MainActor: current: PointerSample; startTicking(_:) -> token (60 Hz while following)
    ReaderPresenting.swift         @MainActor: present(sessionID:content:chrome:intents:), update(...), pin(), dismiss() async
    HotkeyRegistering.swift        (changed) HotkeyEvent handler + press-only convenience
    PreferencesStore.swift         (changed) readerHotkey, followingUnit, pinnedUnit, readerDenylist, readerHideFromScreenSharing, readerOCR
  Reading/
    ReaderGesture.swift            pure tap/hold machine on event timestamps (§3.1)
    ReadPlan.swift                 pure next-step decision (§4.3)
    ReadTextChooser.swift          pure ladder (§3.3)
    TextSegmenter.swift            pure unit-in-window + offset mapping + cap
    PointerThrottle.swift          pure re-read decision (§4.4)
    FallbackTextReader.swift       phase 2
    OCRLineMerger.swift            phase 2
  Session/
    ReaderDependencies.swift       textReader, pointer, presenter, notices, preferences, permissions
    ReadingSessionCoordinator.swift idle/following/pinned/closing; synchronous hotkey(_:) that sets the phase
                                   before any await; one read in flight; (sessionID, seq) tags; isIdle; close()
  Fakes/
    StubTextReader.swift           scripted results, with optional delay and per-point answers (for race tests)
    ScriptedPointer.swift          settable sample + manual tick
```
`Notice` gains `.nothingToRead`, `.readerNeedsAccessibility`, `.readerMenuHint(KeyCombo)`.

### 5.2 Platform (`LargeTextPlatform`)

```
Sources/LargeTextPlatform/
  Reading/
    AccessibilityTextReader.swift  actor on its own serial queue: hit test → stage 0 → ReadPlan loop → chooser;
                                   per-pid back-off; logging under the §4.10 rule
    WindowHitTester.swift          CGWindowList → [WindowInfo]; pure candidate filter
    AXTextRangeReader.swift        native selection + text window + bounds; per-(pid, role) support cache
    AXTextMarkerReader.swift       web units + selection via text markers
    AXElementWalker.swift          bounded child/ancestor walk with secure check on every node
    AXAttributes.swift             typed wrappers (string, CFRange, CGRect, parameterized)
    OCRTextReader.swift            phase 2
  Pointer/
    SystemPointerTracker.swift     PointerSample from CGEvent + NSEvent; 60 Hz Timer in RunLoop `.common` modes
                                   (keeps firing while a menu is open or a drag is tracked), only while ticking
  Focus/
    AXAppPreparer.swift            scoped AXManualAccessibility + 200 ms retry hint (from AccessibilityFocusCapturer)
    AXConfiguration.swift          applyMessagingTimeout(): the single home of the process-wide 0.1 s timeout
    AXGeometry.swift               (changed) + rect conversion for many displays; display-local rect for OCR
  Hotkey/
    CarbonHotkeyRegistrar.swift    (changed) pressed+released, GetEventKind routing, timestamp in callback
  Preferences/
    UserDefaultsPreferencesStore.swift  (changed) reader keys; rejects readerHotkey == hotkey
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
  Editor/ZoomKeyMatcher.swift      extracted from EditorKeyBindings, shared
  Theme/Theme.swift                (changed) followingMaxHeightFraction, highlight metrics
  Previews/ReaderPreviews.swift    label / long paragraph / following / pinned / "No text here" / "Hidden text"
  StatusItem/                      (changed) "Read Text Under Pointer" item
```

### 5.4 Kit (`LargeTextKit`)

- **`AppEnvironment`** gains `textReader`, `pointer` and `reader`. `live()` builds
  `AccessibilityTextReader`, `SystemPointerTracker` and `ReaderWindowController`;
  `readerDependencies()` assembles them.
- **`AppController`:**
  - creates the `ReadingSessionCoordinator`;
  - reader hotkey handler: `{ event in guard editor.isIdle else { return }; reader.hotkey(event) }`.
    This is synchronous; the coordinator starts its own tasks;
  - editor hotkey handler: `{ Task { await reader.close(); await editor.toggle() } }`;
  - status-menu item → `.readerMenuHint`.
- **`Scenario`:**
  - `reader-stub`: `StubTextReader` answers by pointer x (short label / long paragraph / nothing / hidden),
    with a configurable delay so races can be tried by hand;
  - `reader-no-accessibility`;
  - `reader-probe`: the live reader **logs every stage-0 attribute name and the support cache** for the
    element under the pointer once per second. It logs lengths only, under the §4.10 rule. This is the
    harness for spikes R2–R6 and R8.
- **`LaunchConfiguration`:** `--present-reader-on-launch` opens the reader pinned with stub text.

### 5.5 Data flow: hold to read

```
Carbon key-down (stamped) ─▶ AppController ─▶ reader.hotkey(.pressed @t0)       [sync, main actor]
   ReaderGesture: idle → following(t0); seq = 1; Task { await textReader.read(at: pointer.current, unit: .sentence) }
   pointer.startTicking { sample in coordinator.pointerMoved(sample) }         → pendingPoint
read #1 returns (on main actor) ─▶ still following & seq current? ─▶ presenter.present(.following, …)
   pendingPoint passes PointerThrottle? ─▶ read #2 …                          (one in flight)
Carbon key-up (stamped t1, t1 − t0 ≥ 300 ms) ─▶ ReaderGesture → closing
   stop ticking; in-flight result will be dropped; await presenter.dismiss() → idle
```
**Tap** (t1 − t0 < 300 ms):
- `ReaderGesture` moves to pinned and ticking stops.
- If a card is shown: re-segment it to the pinned unit, then `presenter.pin()`.
- If read #1 is still running: present the card pinned when it arrives.

---

## 6. Testing strategy

The existing pattern stays: Swift Testing, pure functions tested directly, coordinators tested with
`Fakes/` and `LargeTextTestSupport` spies.

| Suite | Covers |
|---|---|
| `ReaderGestureTests` | tap, hold and the threshold edge, all from **event timestamps**; press while following handled per the R1 outcome (missed release, or ignored); a poll-created release before `holdThreshold + 100 ms` is impossible (a tap released at 280 ms is never a hold); press while pinned closes and the next release is ignored; a lone release is ignored; max follow duration |
| `ReadingSessionCoordinatorTests` | **Races**, using `StubTextReader` with delays: release (tap) before read #1 finishes → presented pinned; release (hold) before read #1 → nothing presented; a move while a read runs → one follow-up read with the latest point; pin while a read runs → frozen on the last displayed result; a stale `seq` is dropped; a result after close is dropped. **Also:** deduplication, zoom persisting the shared font size, stale-session intents ignored, `.nothing` on tap → HUD, missing permission → HUD, `isIdle` |
| `ReadPlanTests` | step order per role and attribute combination; `.done` early for short static text |
| `ReadTextChooserTests` | the §3.3 ladder; secure **subrole**; hidden found during a walk; denylisted app; web selection vs. native selection; a long `value` is not used as element text; label order |
| `TextSegmenterTests` | units inside a window with offset mapping; window edges; CRLF; emoji and UTF-16 offsets; the cap |
| `PointerThrottleTests` | interval, distance, leaving the frame |
| `FallbackTextReaderTests`, `OCRLineMergerTests` | phase 2 |
| `WindowHitTesterTests` | our own pid skipped; alpha 0; front-to-back order; transparent overlay windows from other apps (HazeOver-like, layer > 0); WindowServer and Dock owners; the 3-candidate cap |
| `AXGeometryTests` | the conversion both ways; a secondary display left of and above the primary with a different height; edge pixels; the display-local OCR rect |
| `CarbonHotkeyRegistrarTests` | routing pressed vs. released through the handler entry point with a fake `EventHotKeyID` and kind |
| `UserDefaultsPreferencesStoreTests` | the reader keys; the duplicate hotkey combo is refused |
| `ReaderPlacementTests` | opposite half; hysteresis (crossing the middle doesn't flip, entering the card does); tall source; small screen; many displays; pin keeps the anchor edge and grows to the pinned cap; direct pin centres |
| `ReaderKeyBindingsTests`, `ZoomKeyMatcherTests` | including ⌘C and ⌘A |
| `ReaderWindowControllerSmokeTests` | present following → not key, `ignoresMouseEvents`, panel sized to the card; pin → `allowsKey`, panel sized to the screen; dismiss |
| `AppEnvironmentTests`, `ScenarioTests` | the new services and scenarios |

**Manual checklist** (`docs/manual-testing.md`):
- clicks actually pass through while following;
- the card never steals focus from the target app while following;
- both gestures over full-screen video and across displays;
- the R2 app matrix;
- observe and record how the panels appear in a screen recording and screen share, with
  `readerHideFromScreenSharing` on and off;
- the editor shortcut while the reader is open.

---

## 7. Spikes

| # | Question | Decides | When |
|---|---|---|---|
| R1 | Is `kEventHotKeyReleased` reliable when a modifier is released first? Does Carbon send auto-repeat presses? Does `CGEventSource.keyState(.combinedSessionState, …)` return real values **without Input Monitoring**? Is `GetEventTime(event)` the real keystroke time? Test: block the main thread for about 500 ms, tap, and compare it with `GetCurrentEventTime()` inside the callback. | Whether the safety poll exists; how auto-repeat is filtered; whether the timestamps can be trusted (if not, document the limitation) | **M0** |
| R4 | Does the system-wide AX hit test skip an `ignoresMouseEvents` panel, both the card **and a highlight outline lying under the pointer**? | How often the `WindowHitTester` fallback runs; single-panel vs. four-edge highlight | **M0** |
| R6 | Cost of a stage-0 read and of a text-window read on a dedicated serial executor; behaviour with a hung app; does the 0.1 s timeout hold? | Budgets, back-off values; confirms the threading decision before the ports freeze | **M0** |
| R2 | Matrix: Safari, Chrome, Arc, Firefox, Mail, Notes, Pages, Preview (PDF), Finder (list/icon), System Settings, Xcode, Terminal, iTerm2, VS Code, Slack, menu bar (including app menus), Dock, Notification Center, **open menus being tracked in another app, Mission Control, Stage Manager strips, the lock/login screen** (should be nothing). Which ladder step, how many calls, how long? | Default units; web scope in v1 | M2 |
| R3 | Chromium browsers: are hit testing and text markers available, with or without `AXManualAccessibility`, and never `AXEnhancedUserInterface`? | Chromium support | M4 |
| R5 | Text markers in WebKit, Chromium, **Gecko (Firefox)** and Electron, including `AXSelectedTextMarkerRange` | Scope of `AXTextMarkerReader` | M4 |
| R7 | OCR: `SCShareableContent` cost; capture and Vision latency with the app-excluding filter; re-confirmation prompts | Automatic vs. explicit OCR | M6 |
| R8 | Terminal and iTerm2: `RangeForPosition` and `StringForRange` windows in scrollback | Window size | M3 |

---

## 8. Milestones

0. **M0: Probe and decide.** Build the `reader-probe` scenario on a minimal `AccessibilityTextReader`
   (hit test + stage 0, on its serial executor). Add `HotkeyEvent` with key-up. Run R1, R4 and R6.
   *Exit:* the `TextReading`, `HotkeyRegistering` and `PointerTracking` signatures are frozen.
1. **M1: Plumbing.**
   - `ReaderGesture` and `ReadingSessionCoordinator` (with all race tests) using fakes;
   - `OverlayPanel.allowsKey`, `ReaderWindowController`, and a **basic `ReaderPlacement` with
     hysteresis**;
   - the `reader-stub` scenario and the editor/reader interplay.

   *Demo:* hold and tap with fake text, including deliberately slow reads.
2. **M2: AX basics.**
   - `ReadPlan`, `ReadTextChooser`, label, value and walk;
   - hidden-content rules (secure subrole, denylist), the permission HUD, the logging rule;
   - the R2 matrix.

   *Demo:* read buttons, menu items and labels anywhere.
3. **M3: Text units.**
   - native selection and text window, `TextSegmenter`, re-segmentation on pin;
   - scroll-to-index on overflow, `HighlightPanel`, `PointerThrottle`;
   - R8.

   *Demo:* hover paragraphs in Notes, Mail, Xcode and Terminal.
4. **M4: Web.** `AXTextMarkerReader`, Chromium detection, scoped `AXManualAccessibility` (R3, R5).
5. **M5: Polish.** Preferences, status-menu hint, shared `CardHeaderView` and `ZoomKeyMatcher`, previews,
   manual checklist.
6. **M6 (phase 2): OCR.** ScreenCaptureKit + Vision, `FallbackTextReader`, Screen Recording permission UI
   (R7).

---

## 9. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Tap seen as hold because of slow reads | Event timestamps taken in the Carbon callback; synchronous gesture handling; reads off the main actor |
| Main-thread jank while following | Dedicated serial AX executor; one read in flight; staged extraction; immediate per-pid back-off |
| Wrong window hit (click-through overlays from other apps) | System-wide hit test first (follows mouse routing); `CGWindowList` only as a capped fallback |
| Poor AX text in some apps (canvas, games, some Electron) | Label and walk ladder; OCR in phase 2; R2 matrix from the probe logs |
| Card covers the pointed-at content or jumps around | Opposite-half placement with hysteresis; click-through; no jump on pin; highlight outline |
| Carbon release lost or key appears stuck | Per R1: press-while-following = missed release, or presses ignored; `keyState` poll after the hold threshold if R1 allows; 30 s cap |
| Secrets shown huge to the room or in a screen share | Secure subrole check on every visited element; password-manager denylist; content never logged; OCR images kept in memory only; opt-in, best-effort `sharingType = .none` |
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
