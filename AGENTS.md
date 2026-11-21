# Notes for agents and contributors

- Build and test: see the README (`swift test` in `packages/LargeTextPackage`).
- Releases are automatic: every pull request merged into `main` is released by
  `.github/workflows/release.yml`. Read [docs/releasing.md](docs/releasing.md) before changing anything in
  `scripts/release/`, the workflow, `xcode/LargeText/Info.plist` or the Sparkle code.
- Don't bump `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` in the Xcode project; the release sets them
  from git tags and the appcast.
- Don't edit `Casks/largetext.rb` by hand; `scripts/release/update-cask.sh` writes it.
- App icon: the master is `design/icons/AppIcon-master.png` (full-bleed square art). Don't edit the PNGs in
  `AppIcon.appiconset` by hand; run `design/icons/make-app-icon.sh`, which writes them. Unused icon options
  and the prompts that generated them are in `design/icons/options/` (an icon picker in Settings is a
  postponed idea).
- Pull requests: fill in the "Release notes" section and use the `release:minor`, `release:major` or
  `skip-release` labels as needed.
