# LargeText — manual testing

Hands-on checklist for milestone 6 (see `IMPLEMENTATION_PLAN.md` §4 and §5). Nothing here has been run yet.
Tick items as you go and write the observed numbers and surprises next to them; they feed the PRD.

## Setup

- Build and run the `LargeText` scheme from `xcode/LargeText/LargeText.xcodeproj`, signed with your real
  development team (not "Sign to Run Locally"). TCC keys on the designated requirement, so never change the
  bundle id (`com.actondon.LargeText`) or signing identity between builds.
- The app is menu-bar only (`LSUIElement`). Look for the **textformat.size** icon. Default hotkey: **⌃⌥⌘T**.
- On first launch the system Accessibility prompt appears once. Grant LargeText under
  *System Settings › Privacy & Security › Accessibility*.

### Logs

```sh
log stream --predicate 'subsystem == "LargeText"' --level debug
```

Categories: `Kit` (startup, scenario, hotkey failure), `Core` (session phases, capture time, focus-return
pid and time, insertion route, restore outcome), `Platform` (AX, hotkey registration, posted keys,
permissions incl. `secureEventInput`), `UI` (overlay present/dismiss, lost focus, HUD text).
Add `--style compact` for shorter lines. Text content is logged `private` (shows as `<private>` unless a
logging profile is installed).

### Escape hatches

```sh
# Reset the Accessibility grant (after changing signing, or to re-test the first-launch flow)
tccutil reset Accessibility com.actondon.LargeText

# Don't snapshot/restore the clipboard (avoids macOS 15.4+ pasteboard privacy prompts).
# The HUD then says "Inserted — your clipboard now contains this text".
defaults write com.actondon.LargeText LargeText.clipboardRestore none
defaults delete com.actondon.LargeText LargeText.clipboardRestore   # back to the default (restore, 10 MB)

# Other preferences
defaults write com.actondon.LargeText LargeText.fontSize -float 96
defaults read  com.actondon.LargeText
```

### Scenarios

Set *Product › Scheme › Edit Scheme… › Run › Arguments › Arguments Passed On Launch* (add one entry per
argument and tick only the set you want), or launch the built app from a terminal:

```sh
open -n /path/to/LargeText.app --args --scenario overlay-prefilled --present-on-launch
```

| Arguments | What you get | What stays live |
|---|---|---|
| `--scenario overlay-prefilled --present-on-launch` | Overlay opens immediately, "Typing into Safari", prefilled with `https://www.apple.com` (selected). Commit only logs (`LoggingTextInserter`). | Hotkey, status item, permissions, overlay, HUD |
| `--scenario no-editable-target` | Every session targets a non-editable Safari element; commit copies to the clipboard and shows the "Copied — press ⌘V · No text field was focused" HUD. | Permissions, real pasteboard + inserter, overlay, HUD |
| `--scenario permission-missing` | Permissions report denied (no system prompt); header shows the will-copy hint; commit is copy-only with the "Copied — press ⌘V · Accessibility permission is missing" HUD. | Focus capture, real pasteboard + inserter, overlay, HUD |
| `--scenario logging-insertion` | Everything live, but commit only logs instead of pasting. Good for testing capture/overlay in risky apps. | Everything except the inserter |
| `--present-on-launch` (alone) | Opens the editor right after launch against whatever was frontmost. | Everything |

All scenarios use in-memory preferences (zoom isn't persisted). Unknown scenario names are logged
(`Kit` category) and ignored. Note: with `--present-on-launch`, the launch-time
Accessibility prompt is skipped (the overlay would cover it); use *Grant Access…* in the status menu instead.

## Spike items (§5 milestone 0)

The timing defaults are the plan's starting values: `focusReturnDelay` 50 ms, `pollInterval` 20 ms,
`maxModifierPolls` 15, `restoreDelay` 600 ms (`InsertionTiming.default`). Adjust them from these results.

- [ ] **0a Focus return.** In Safari, Chrome and an Electron app (Slack/VS Code): open, type, ↩. Does the
  text land in the original field? From `Core` logs note the focus-return time and whether the focused
  pid matched; compare frontmost pid with `kAXFocusedApplication` pid. Does focus return at the start or
  at the end of the fade (try with *Reduce Motion* on and off)? → sets `focusReturnDelay`.
- [ ] **0b Full-screen video.** Full-screen a video (Safari/YouTube, QuickTime, TV app). Hotkey: overlay
  visible above the video on that Space? HUD visible too?
- [ ] **0c Chrome omnibox.** ⌘V via `CGEvent` reaches the omnibox; ⌘↩ submits.
- [ ] **0e Input methods in the panel.** Japanese IME (↩ confirms composition, does not commit), Dictation,
  Character Viewer (⌃⌘Space — expected: clicking into it cancels with the draft kept). ⌘Z / ⌘⇧Z / ⌘X /
  ⌘C / ⌘V / ⌘A inside the non-activating panel.
- [ ] **0f Resign-key.** During a session: ⌘Tab, Spotlight (⌘Space), screen lock, click on another display.
  Each should cancel (`UI`: "lost key status → cancel(.lostFocus)") and keep the draft (reopen → draft
  selected).
- [ ] **0g Hotkey failure.** Register ⌃⌥⌘T in another app first (or set a conflicting combo via
  `defaults write … LargeText.hotkey`): does `RegisterEventHotKey` return an error (HUD "shortcut
  unavailable" + status-menu row) or silently never fire? Does the hotkey fire under Secure Input (focus a
  password field in Terminal/1Password) and while our own panel is key (toggle = commit)?
- [ ] **0h Pasteboard privacy prompt.** On this macOS version: does the snapshot/restore trigger a prompt?
  Does ⌘V *inside the editor* trigger one, and does it appear under the overlay? If prompts are a problem,
  try `LargeText.clipboardRestore none`.
- [ ] **0i Permission granted mid-run.** Start without access (`tccutil reset …`), grant it while running.
  Does posting work without relaunch? The status menu shows "Relaunch to finish setup" when AX is granted
  but posting isn't.
- [ ] **0j Electron.** LargeText sets `AXManualAccessibility = true` once per Electron process (detected by
  `Contents/Frameworks/Electron Framework.framework`; log line `AXManualAccessibility on …`). In VS Code /
  Signal / Slack: open the overlay twice with some text selected. The first capture may be empty (the
  tree builds asynchronously); the second should log `kind=…` and `hasSelection=true` and prefill the
  selection. Also check the Electron app doesn't feel slower afterwards.

(There is no item 0d in the plan.)

## Manual matrix (§4)

For each target: open with the hotkey (with and without a selection), edit, then ↩ (insert) and ⌘↩
(insert & submit). Check the text landed, the clipboard was restored afterwards (copy something first),
and the log durations.

### Targets

- [ ] Safari URL bar (selection prefill; ⌘↩ navigates; note how the field handles pasted line breaks)
- [ ] Chrome omnibox (element usually unknown → still pastes)
- [ ] Firefox URL bar and a web text field
- [ ] TextEdit (multi-line; ⇧↩ newlines preserved)
- [ ] Notes
- [ ] Slack (Electron)
- [ ] VS Code (Electron)
- [ ] Gmail compose in a browser (contenteditable; `AXGroup`/`AXWebArea` → unknown → paste)
- [ ] Terminal (multi-line text is pasted as-is; check the terminal's bracketed-paste / multi-line paste warning)
- [ ] iTerm2 (same)
- [ ] A password field (Safari login form, System Settings) → HUD "Password fields aren't supported",
      overlay never shown
- [ ] Non-editable target (Finder with an icon selected) → copy-only HUD, text on the clipboard
- [ ] LargeText itself frontmost (status menu → *Open Large Editor*) → copy-only

### Environment

- [ ] Full-screen video (overlay and HUD above it)
- [ ] Two displays: overlay appears on the target's screen; the other screen's status item *Open Large
      Editor* commits like the hotkey
- [ ] Dvorak layout: ⌘V lands (ASCII-capable layout key code); zoom keys work
- [ ] Russian layout: same
- [ ] Japanese IME inside the editor
- [ ] ⌘Tab during a session → cancel, draft kept
- [ ] Screen lock during a session → cancel, draft kept
- [ ] ⌘V inside the editor pastes the current clipboard
- [ ] Hold ⌘ after ⌘↩ (keep holding) → copy-only "Keys were still held down" HUD, no ⌘↩ new tab
- [ ] Switch apps right after committing (fast ⌘Tab) → `targetChanged` copy-only

### Overlay behaviour

- [ ] ↩ insert · ⌘↩ insert & submit · ⇧↩/⌥↩ newline · ⎋ cancel (draft kept) · backdrop click cancel
- [ ] ⌘= / ⌘+ / ⌘- / ⌘0 zoom; size persists across sessions (not in scenarios)
- [ ] Empty commit closes without inserting and leaves the draft untouched
- [ ] Leading/trailing spaces, tabs and whitespace-only text are inserted exactly as typed
- [ ] Hotkey while open = commit
- [ ] Status menu: permission row (granted ✓ / Grant Access… / Relaunch), Quit

### Numbers to record

From `Core` logs per session: capture time, focus-return time and pid, paste time, restore outcome
(restored / skipped because the pasteboard changed / lossy).

## Deliberate deviations from the plan (confirm during hands-on)

- **IME composition on commit:** `dismiss()` calls `discardMarkedText()` and then `unmarkText()`, so an
  unfinished Japanese/Chinese composition is *kept* in the committed text rather than dropped (§2.3 says
  discard). Check which behaviour feels right with a Japanese IME.
- **Text is inserted verbatim:** whitespace and line breaks are never altered; the target field decides
  how to handle them (plan revision 5).
- **Back-to-back commits:** a second commit within the 600 ms window reuses the first commit's
  clipboard snapshot, so the user's original clipboard is what comes back. Quitting flushes a pending one.
- **Not yet measured:** clipboard snapshot cost with very large clipboard contents (e.g. a big image);
  watch the `Insertion: pasted … after …` log line during spike 0h.

## Reader

Hands-on checklist for the reader (see `READER_IMPLEMENTATION_PLAN.md` §6 and §7). Default shortcut:
**⌃⌥⌘R**. Hold it to follow the pointer (the card shows the sentence under it and closes on release); tap
it to pin the paragraph (⎋ closes, ⌘C copies, ⌘± zooms). It needs the same Accessibility grant as the
editor.

### Reader logs

```sh
# Everything, including each read's stage 0 and steps and each hotkey event's timestamps
log stream --predicate 'subsystem == "LargeText"' --level debug

# One line per read and per probe tick only
log stream --predicate 'subsystem == "LargeText" AND (category == "Platform" OR category == "Kit")' --level info --style compact
```

- `Platform`, one `Read in … ms, N AX calls: app=… role=… subrole=… steps=[…] … result=…` line per read
  (info). `result` is `text(source=…, granularity=…, length=…)`, `hidden`, `nothing`, `ownWindow` (the hit
  landed on our own card or highlight) or `permissionMissing`; `aborted=cannotComplete` means the app was
  busy or the 0.1 s timeout expired. At debug level also `Stage 0: …`, `Step … in … ms` and
  `Hotkey N pressed|released: eventTime=… currentEventTime=… nsEventTime=…`.
- `Core`: `Reader: idle → following` and the other phase changes, `Reader session …: closing (reason)`.
- `UI`: `Reader presented (following|pinned)`, `Reader pinned`, `Reader dismissed`, lost key status.
- `Kit`: the probe's lines (below).

Under the privacy rule (plan §4.10) the reader never logs text from another app, not even as `<private>`:
only roles, steps, lengths, durations, AX error codes and bundle IDs.

### Reader scenarios and tunables

| Arguments | What you get |
|---|---|
| `--scenario reader-stub` | A stub reader that answers by the pointer's global x in 400 pt bands from the left edge of the primary display: a short label ("Open Large Editor"), a long paragraph, nothing ("No text here"), then "Hidden text" from 1 200 pt on. Permissions report granted and the editor only logs its commits. Hotkeys, pointer, key state, panel and HUD are live. |
| `--reader-stub-delay <ms>` (with any stub) | The stub waits that long before answering, so release-before-first-read and slow reads can be tried by hand. |
| `--present-reader-on-launch=pinned` | Right after launch, a scripted tap: the pinned card with the short label. Implies `reader-stub`. |
| `--present-reader-on-launch=following` | A scripted press with no release, over the live pointer and the 400 pt bands: watch placement and hysteresis without holding four keys. The key counts as held and the 30 s cap is off; press ⌃⌥⌘R (a missed release) or the editor shortcut to close it. |
| `--present-reader-on-launch=nothing` / `hidden` / `long` | A scripted tap: the "No readable text under the pointer" HUD / the pinned "Hidden text" card / a pinned paragraph long enough to scroll. |
| `--scenario reader-no-accessibility` | Permissions report denied (no system prompt): the reader shortcut shows "Allow Accessibility to read text" and the status menu offers *Grant Access…*. |
| `--scenario reader-probe` | Everything live, plus the probe that logs the element under the pointer once per second (spikes below). |
| `--reader-hold-threshold <ms>` | Tap vs. hold threshold (default 300). In memory only; never written to the defaults. |
| `--following-unit sentence\|line\|paragraph` | The unit while following (default sentence). In memory only. |

The persistent preferences, for when a value has been chosen:

```sh
defaults write com.actondon.LargeText LargeText.readerHoldThreshold -int 250
defaults write com.actondon.LargeText LargeText.followingUnit line          # sentence | line | paragraph
defaults write com.actondon.LargeText LargeText.pinnedUnit paragraph
defaults delete com.actondon.LargeText LargeText.readerHoldThreshold        # back to the default
```

### Spikes with `--scenario reader-probe`

Launch with `--scenario reader-probe` and keep `log stream --predicate 'subsystem == "LargeText"' --level debug`
running. Once per second the probe logs, for the element under the pointer:

```
Probe in 2.3 ms, 3 AX calls: app=com.apple.Notes pid=… family=native role=AXTextArea subrole=nil lengths=[…] characterCount=18234 hasFrame=true webArea=false
Probe attributes: AXFrame, AXRole, …
Probe parameterized: AXBoundsForRange, AXRangeForPosition, AXStringForRange, …
```

or `Probe: own process under the pointer`, `Probe: no element (AX error …)`, `Probe: Accessibility not
trusted`. The reader shortcut keeps working, so each spike can also watch the reader's own `Read in …` lines.

- [ ] **R1 Key-up, auto-repeat, key state, timestamps.** Hold ⌃⌥⌘R in Notes for 3 s.
  - Auto-repeat: count the `Hotkey N pressed` lines. More than one means Carbon repeats, and the reader
    then closes after the first repeat (`Core`: `following → closing`, a press is a missed release).
  - Release a modifier first (⌘, then R): is there a `Hotkey N released` line, and does the card close?
  - Key state: from 400 ms after the press the reader asks `CGEventSource.keyState` on every pointer tick.
    If a held shortcut closes on its own with `closing (keyReleased)`, the call is gated by Input
    Monitoring: switch `AppEnvironment.live()` to `SystemKeyStateReader(mode: .modifierFallback)`.
  - Timestamps: on each `Hotkey` line, `eventTime` should equal the keystroke time, `currentEventTime` is
    when the callback ran, and `nsEventTime` is the window server's base. For the blocked-main-thread
    variant add a temporary `usleep(500_000)` at the start of `AppController.readerHotkey(_:)` for the
    pressed phase and tap quickly: the release line's `currentEventTime` should be about 0.5 s after its
    `eventTime`, and the gesture should still be a tap (a pinned card, not a closed hold).
- [ ] **R4 Does the hit test skip our click-through windows?** Hold ⌃⌥⌘R over a paragraph in Notes: the
  highlight outline lies under the pointer. If the hit test skips it, the `Read in …` lines keep showing
  `result=text(…)` and the probe keeps logging Notes; if not, they show `result=ownWindow` and
  `Probe: own process under the pointer`, and the card stops updating. The card itself moves away from the
  pointer while following; to put the pointer on it, use `--present-reader-on-launch=following` and move
  quickly onto the card before it flips halves, and note whether clicks there reach the app below. A
  pinned card accepts the mouse, so the probe reporting our own process over it is expected. Record the
  result: it decides whether `WindowHitTester` and the four-edge highlight are needed.
- [ ] **R6 Cost and the timeout.** In Notes, Mail, Xcode, Terminal, Safari and Slack, hover with the probe
  and hold the reader. From the `Read in … ms, N AX calls` lines record typical and worst durations and
  call counts per app and per `steps=[…]` (budget: first card within 100 ms of key-down, following updates
  under 50 ms); from the `Probe in … ms` lines the stage-0 cost and the parameterized-name count. Hung app:
  `kill -STOP <pid>` a running app, hover over its window and hold the reader: each read should end in
  about 0.1 s with `aborted=cannotComplete` (and nothing on the card), and the next read in another app
  should not be delayed by more than about 0.2 s. Then `kill -CONT <pid>`. The plan's comparison with a
  `value` read of a 1 MB `AXTextArea` isn't in the probe: note the `characterCount` and window timings
  instead, or measure `value` with a temporary change. These numbers decide whether per-pid back-off and
  a support cache are needed.

#### Web content (R3, R5)

The web path reads text markers on the page's `AXWebArea` (plan §4.3): in a web area `steps=[…]` is
`selection, textMarkers` and a hit gives `result=text(source=unit, …)` (or `source=selection` over a
selection). At debug level each step also logs, with attribute names and lengths only:

```
Text markers: AXSentenceTextMarkerRangeForTextMarker length=84 segmented=false pointerOffset=-1 shownLength=84 hasBounds=true
Text markers: AXSentenceTextMarkerRangeForTextMarker gave no text
Text markers: AXParagraphTextMarkerRangeForTextMarker length=412 segmented=true pointerOffset=133 shownLength=61 hasBounds=true
Text markers: … unit not under the pointer
Text markers: no AXWebArea above the hit element
```

`segmented=true` is the Gecko fallback: sentence ranges were missing or empty, so the paragraph (else the
line) was fetched and cut to the sentence at `pointerOffset`, the length of the text from the paragraph's
start to the pointer's marker. `pointerOffset=-1` there means the offset was unknown and the whole paragraph
is shown. The highlight then outlines the paragraph, not the sentence. The `Probe parameterized:` line lists
which marker attributes an element offers. For each check, hover over body text, a link, a heading and an
image, then select a few words and hover over the selection and next to it.

- [ ] **R5 Safari (WebKit).** Expect `webArea=true`, `steps=[selection, textMarkers]`, `segmented=false`,
  the sentence outlined, and a selection read only while the pointer is on it. Repeat in Mail (an HTML
  message).
- [ ] **R3 Chrome, as it starts (no `AXManualAccessibility` yet).** Quit Chrome, relaunch it, and hold over a
  page with nothing else reading it (no VoiceOver, no other AX client). Note what the first read shows: an
  empty `role=AXWebArea` or `AXGroup` hit, `AXManualAccessibility on com.google.Chrome: enabled` (`Platform`,
  info), then `retried=true`. Record whether the retry already gives `source=unit` or only later reads do.
- [ ] **R3 Chrome with `AXManualAccessibility`.** Keep holding after that line: expect the same steps as
  Safari. Record whether hit testing and markers worked *before* the attribute was set (then R3 says Chrome
  doesn't need it). Repeat in Arc or Brave. `grep -rn AXEnhancedUserInterface packages` must stay limited to
  the comment that says it is never set.
- [ ] **R5 Firefox (Gecko).** Expect `segmented=true` on `AXParagraphTextMarkerRangeForTextMarker` if Gecko
  has no sentence ranges. Check that the shown sentence is the one under the pointer at the start, middle and
  end of a long paragraph, and in a paragraph with a link or bold text in it (the offset heuristic may drift
  there). Note whether `AXSelectedTextMarkerRange` gives `source=selection`.
- [ ] **R5 Electron (Slack or VS Code).** The first read sets `AXManualAccessibility` (as for Chrome). In
  Slack hover over messages; in VS Code over the Markdown preview or the welcome page (the editor itself is a
  native-looking text area with its own path). Expect `source=unit`.
- [ ] Pin in each browser: the web sentence stays as it is (no paragraph re-read in v1). Note any page where
  that feels wrong; it decides the deferred `pinSeq` paragraph read.
- [ ] Record per engine: which marker attributes exist, `steps`, `segmented`, AX call count and duration.
  These decide the scope of `AXTextMarkerReader` and whether the sentence fallback is enough.

### Reader checklist

- [ ] Hold over text: the card follows, never takes focus from the app (its window stays key, the caret
      keeps blinking), and clicks pass through the card and the highlight while following.
- [ ] Release closes; a quick tap pins the paragraph; ⎋, a backdrop click, ⌘Tab and the shortcut again
      close the pinned card. ⌘C copies, ⌘A selects, ⌘± / ⌘0 zoom and the size is shared with the editor.
- [ ] Tap on nothing → HUD "No readable text under the pointer"; following over nothing → quiet
      "No text here" card.
- [ ] A password field, 1Password, Keychain Access and Passwords → "Hidden text"; nothing about them in the
      logs apart from the bundle ID and role.
- [ ] Both gestures over full-screen video and on a second display (the card opens on the pointer's
      display, in the half away from the pointer, and only changes halves when the pointer reaches it).
- [ ] The editor shortcut while the reader is following, pinned and fading: the reader closes first and the
      editor opens exactly once. The reader shortcut while the editor is open does nothing.
- [ ] Status menu *Read Text Under Pointer (⌃⌥⌘R)* shows the HUD "Point at text and press ⌃⌥⌘R".
- [ ] Set the reader shortcut equal to the editor's (`defaults write com.actondon.LargeText LargeText.readerHotkey -dict keyCode -int 17 modifiers -int 7`,
      then relaunch): the reader isn't registered, the HUD says the shortcut is unavailable and the status
      menu lists it. `defaults delete com.actondon.LargeText LargeText.readerHotkey` restores it.
- [ ] Revoke Accessibility while following (`tccutil reset Accessibility com.actondon.LargeText`): the
      card closes and the Accessibility HUD shows once.
- [ ] Record a screen recording and a screen share (FaceTime or Zoom) with the card following and pinned,
      and note how both panels appear; this is the evidence for the deferred `readerHideFromScreenSharing`.
- [ ] **R2 app matrix.** With `--scenario reader-probe`, hover and hold in Safari, Chrome, Arc, Firefox,
      Mail, Notes, Pages, Preview (PDF), Finder (list and icon view), System Settings, Xcode, Terminal,
      iTerm2, VS Code, Slack, the menu bar (including app menus), the Dock, Notification Center, an open
      menu being tracked in another app, Mission Control, Stage Manager strips and the lock screen
      (expected: nothing). Note per app the `steps=[…]`, `source`, call count and duration, and any hover
      side effects of holding ⌃⌥⌘ (Xcode ⌘-hover links, ⌥ in Finder, macOS Hover Text). Web content in
      browsers and Electron apps goes through text markers: see *Web content (R3, R5)* above.
