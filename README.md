# LargeText

A macOS menu-bar prototype: press **⌃⌥⌘T** anywhere and a huge, readable editor appears over the
current app (even full-screen video). Type, then press ↩ to put the text into the field that had focus
(⌘↩ also presses Return, e.g. to submit a URL or search). See `idea.md` for the motivation and
`IMPLEMENTATION_PLAN.md` for the design.

## Layout

```
packages/LargeTextPackage/   Swift package "LargeText" (all the code)
  Sources/LargeTextCore/       models, ports, session coordinator, insertion logic, fakes
  Sources/LargeTextPlatform/   live adapters: Carbon hotkey, AX focus, pasteboard, CGEvent, defaults
  Sources/LargeTextUI/         overlay panel & editor, HUD, status item, #Previews
  Sources/LargeTextKit/        composition root, scenarios, public entry point
  Tests/                       Swift Testing suites + LargeTextTestSupport (spies)
xcode/LargeText/             host AppKit app: main.swift calls LargeTextApplication.run()
docs/manual-testing.md       hands-on checklist, spike items, logging & reset commands
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

Details, logging (`log stream --predicate 'subsystem == "LargeText"' --level debug`) and reset commands are
in [docs/manual-testing.md](docs/manual-testing.md).
