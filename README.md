# LargeText

A macOS menu-bar prototype: press **⌃⌥⌘T** anywhere and a huge, readable editor appears over the
current app (even full-screen video). Type, then press ↩ to put the text into the field that had focus
(⌘↩ also presses Return, e.g. to submit a URL or search). See `idea.md` for the motivation and
`IMPLEMENTATION_PLAN.md` for the design.

**Reader.** Point at any text and press **⌃⌥⌘R** to see it large. Hold the shortcut and the card follows
the pointer, showing the sentence under it, and closes on release; tap it and the card pins the paragraph so
you can scroll, copy (⌘C) or zoom (⌘±), then ⎋ closes it. Password fields and password managers show
"Hidden text". It reads through the Accessibility API and needs the same grant as the editor. See
`READER_IMPLEMENTATION_PLAN.md`.

**Settings.** Open it with *Settings…* in the status menu, with ⌘, in the editor or on the pinned reader card
(the editor closes first; text you typed is copied to the clipboard and kept as the draft, as with ⎋), or
by itself on the first launch when Accessibility is missing. It controls:

- both shortcuts, recorded in place: the editor's can be changed or reset; the reader's can also be turned
  off, which leaves *Read Text Under Pointer* out of the menu;
- separate text sizes for the editor and the reader (⌘± changes the one in use; an existing reader size
  starts at the editor size);
- the reader's hold threshold and the units it shows while following and when pinned;
- restoring the clipboard after pasting;
- Accessibility access (*Grant Access…* or *Relaunch*) and launch at login;
- automatic update checks and *Check Now* (release builds only);
- *Reset All Settings…* (leaves launch at login alone).

Changes apply at once or on the next session; nothing needs a relaunch. While Settings is open, LargeText
shows a Dock icon, a ⌘Tab entry and a small main menu (About, Settings…, Hide, Quit, Edit, Window); closing it
makes the app menu-bar only again and returns focus to the previous app. The status menu has *Open Large
Editor*, *Read Text Under Pointer* (unless turned off), the Accessibility item, *Settings…*, *Check for
Updates…* (release builds only) and *Quit*. See
`SETTINGS_IMPLEMENTATION_PLAN.md`.

## Install

Requires macOS 14 or later.

- **Download** the DMG from the [latest release](https://github.com/atacan/LargeText/releases/latest), open
  it and drag LargeText to Applications.
- **Homebrew** (this repository is its own tap):

  ```sh
  brew tap atacan/largetext https://github.com/atacan/LargeText
  brew install --cask largetext
  ```

LargeText updates itself (*Check for Updates…* in the status menu, and daily checks you can turn off in
Settings). Releases are signed with Developer ID and notarized by Apple; see
[docs/releasing.md](docs/releasing.md) for how they are made.

## Layout

```
packages/LargeTextPackage/   Swift package "LargeText" (all the code)
  Sources/LargeTextCore/       models, ports, session coordinator, insertion logic, fakes
  Sources/LargeTextPlatform/   live adapters: Carbon hotkey, AX focus and reading, pointer, pasteboard, CGEvent, defaults
  Sources/LargeTextUI/         overlay panel & editor, reader card, HUD, status item, #Previews
  Sources/LargeTextKit/        composition root, scenarios, public entry point
  Tests/                       Swift Testing suites + LargeTextTestSupport (spies)
xcode/LargeText/             host AppKit app: main.swift calls LargeTextApplication.run()
docs/manual-testing.md       hands-on checklist, spike items, logging & reset commands
docs/releasing.md            how a merged pull request becomes a release; one-time setup
scripts/release/             the release steps (build & notarize, appcast, GitHub release, cask)
Casks/largetext.rb           the Homebrew cask, rewritten by every release
```

## Build & test

Requires Xcode 16+ (Swift 6 toolchain with Swift Testing); developed with Xcode 27.

```sh
cd packages/LargeTextPackage
swift build --build-tests
swift test
```

App: open `xcode/LargeText/LargeText.xcodeproj` and run the `LargeText` scheme, or

```sh
xcodebuild -project xcode/LargeText/LargeText.xcodeproj -scheme LargeText -configuration Debug \
  -destination 'platform=macOS' build
```

Sign Debug builds with your real development team and keep the bundle id stable, otherwise the
Accessibility grant is lost on every build. The app is not sandboxed and needs Accessibility access to
read the focused field and to paste; without it, commits fall back to copying to the clipboard.

## Scenarios

Launch arguments swap in fakes for hands-on testing (*Edit Scheme › Run › Arguments Passed On Launch*):

- `--scenario overlay-prefilled --present-on-launch` — editor opens prefilled for a stub Safari; commit only logs
- `--scenario no-editable-target` — commit is copy-only (no editable target)
- `--scenario permission-missing` — permissions reported as denied; commit is copy-only
- `--scenario logging-insertion` — everything live, but commit only logs
- `--present-on-launch` — open the editor right after launch
- `--scenario reader-stub` — the reader shows stub text chosen by the pointer's x position
- `--present-reader-on-launch=pinned|following|nothing|hidden|long` — a reader card in that state right after launch
- `--scenario reader-no-accessibility` — the reader shortcut shows the Accessibility HUD
- `--scenario reader-probe` — logs what the element under the pointer exposes, once per second (spikes)
- `--present-settings-on-launch` — open Settings right after launch
- `--scenario settings-hotkey-taken` — ⌃⌥⌘E and ⌃⌥⌘Y are refused as if another app held them
- `--scenario settings-needs-relaunch` — Accessibility granted but event posting denied: Settings offers *Relaunch*
- `--scenario first-launch` — a first launch with access denied: Settings opens by itself

Every scenario keeps preferences and launch at login in memory, and turns updates off, so nothing reaches
the real defaults or the system's login items, and nothing is downloaded.

Details, logging (`log stream --predicate 'subsystem == "LargeText"' --level debug`) and reset commands are
in [docs/manual-testing.md](docs/manual-testing.md).

## License

MIT; see [LICENSE](LICENSE).
