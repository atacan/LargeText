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
(`Kit` category) and ignored. Note: if Accessibility is missing at launch, the system prompt appears and
`--present-on-launch` may cover it — grant access first.

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
- [ ] **0j Electron.** Whether setting `AXManualAccessibility = true` on an Electron app element is needed
  for focus/selection reads (not implemented in v1; note what `Platform` logs report for role/selection).

(There is no item 0d in the plan.)

## Manual matrix (§4)

For each target: open with the hotkey (with and without a selection), edit, then ↩ (insert) and ⌘↩
(insert & submit). Check the text landed, the clipboard was restored afterwards (copy something first),
and the log durations.

### Targets

- [ ] Safari URL bar (selection prefill; single-line → newlines flattened; ⌘↩ navigates)
- [ ] Chrome omnibox (element usually unknown → still pastes)
- [ ] Firefox URL bar and a web text field
- [ ] TextEdit (multi-line; ⇧↩ newlines preserved)
- [ ] Notes
- [ ] Slack (Electron)
- [ ] VS Code (Electron)
- [ ] Gmail compose in a browser (contenteditable; `AXGroup`/`AXWebArea` → unknown → paste)
- [ ] Terminal (newline-flattening hint in the header; multi-line text arrives as one line)
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
- [ ] Blank commit closes without inserting and leaves the draft untouched
- [ ] Hotkey while open = commit
- [ ] Status menu: permission row (granted ✓ / Grant Access… / Relaunch), Quit

### Numbers to record

From `Core` logs per session: capture time, focus-return time and pid, paste time, restore outcome
(restored / skipped because the pasteboard changed / lossy).
