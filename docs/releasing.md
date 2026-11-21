# Releasing

Every pull request merged into `main` becomes a release, with nothing to do by hand:
[`.github/workflows/release.yml`](../.github/workflows/release.yml) builds the app, signs it with Developer
ID, notarizes it, publishes a GitHub release with the DMG, updates the Sparkle feed and the Homebrew cask.

## What decides a release

| On the pull request | Effect |
|---|---|
| no label | patch release (0.1.0 → 0.1.1) |
| `release:minor` | 0.1.3 → 0.2.0 |
| `release:major` | 0.4.2 → 1.0.0 |
| `skip-release` | nothing is released |
| a `## Release notes` section in the description | the notes (Markdown) shown in the update window and on the release |
| no such section | the pull request title is the note |

The PR template has the section ready. A merge that only changes `docs/`, Markdown files or `Casks/` doesn't
start the workflow. A direct push to `main` is released as a patch, with the commit subject as its note. You
can also run **Actions › Release › Run workflow** and pick the bump and the notes.

Releases run one at a time. If several merges land while one is building, only the newest one waits; when
it runs, it builds the newest commit, so nothing is lost. The skipped merges' notes don't appear in it,
though.

## Versions

- **Marketing version** (`CFBundleShortVersionString`): the newest `vX.Y.Z` tag, bumped. The first release
  is `0.1.0`. The workflow creates the tag with the release.
- **Build** (`CFBundleVersion`, which Sparkle compares): the highest build in the current appcast plus one.
- Both are passed to `xcodebuild` as build settings. Nothing is written back to the project, which stays at
  `0.0.0 (0)` for local builds. Don't bump `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` by hand.

## Where things live

| What | Where |
|---|---|
| DMG | Release asset `LargeText-X.Y.Z.dmg` on tag `vX.Y.Z` |
| Sparkle feed | Release asset `appcast.xml`. Every release carries the whole feed, and the app reads `https://github.com/atacan/LargeText/releases/latest/download/appcast.xml` (`SPARKLE_FEED_URL` in the Xcode project). |
| Homebrew cask | [`Casks/largetext.rb`](../Casks/largetext.rb) on `main`, rewritten and committed by each release. This repository is the tap: `brew tap atacan/largetext https://github.com/atacan/LargeText`, then `brew trust atacan/largetext` (recent Homebrew refuses untrusted third-party taps). |
| Sparkle public key | `SPARKLE_PUBLIC_ED_KEY` in the Xcode project, which goes into `Info.plist` through [`xcode/LargeText/Info.plist`](../xcode/LargeText/Info.plist) |

Because the feed URL is `releases/latest`, never mark a release as a pre-release or edit which release is
"latest" by hand: the latest release must be the newest one, with its `appcast.xml`.

## The steps

Each step is a script in [`scripts/release/`](../scripts/release) that takes its inputs from the
environment, so CI and a local run do the same thing:

1. `resolve-release.sh` reads the merged PR: skip or not, the bump, the notes; `next-version.sh` turns the
   bump into a version.
2. `fetch-appcast.sh` downloads `appcast.xml` from the latest release and picks the next build number.
3. `import-signing-certificate.sh` (CI only) puts the Developer ID certificate in a temporary keychain and
   writes the App Store Connect key.
4. `build-dmg.sh` archives with manual Developer ID signing, exports, notarizes and staples the app, then
   makes the DMG with `hdiutil`, signs, notarizes and staples it, and checks both with Gatekeeper. It refuses
   to build while `SPARKLE_PUBLIC_ED_KEY` is empty.
5. `update-appcast.sh` runs Sparkle's `generate_appcast` on the previous feed plus the new DMG and its
   notes. Earlier items keep their own URLs; the new one is signed with the EdDSA key. It fails if the new
   item isn't signed, which is what happens when the private key doesn't match the app's public key.
6. `publish-release.sh` creates the release as a draft, uploads the DMG and `appcast.xml`, then publishes
   it as the latest release, so the feed never points at a release without its files.
7. `update-cask.sh` rewrites the cask with the new version and SHA-256, commits it and pushes it to `main`.
   That push uses `GITHUB_TOKEN`, so it doesn't start another release.

## One-time setup

### 1. Sparkle keys

Build the app once (for example with Xcode) so Sparkle's tools are downloaded, then:

```sh
SPARKLE_BIN="$(find ~/Library/Developer/Xcode/DerivedData -path '*/artifacts/sparkle/Sparkle/bin' -type d | head -n 1)"
"$SPARKLE_BIN/generate_keys"          # creates the key in your login keychain and prints the public key
"$SPARKLE_BIN/generate_keys" -x sparkle-private-key.txt   # exports the private key for CI
```

Put the public key in the Xcode project: `SPARKLE_PUBLIC_ED_KEY` in both configurations of the LargeText
target, replacing `""`, and commit it. It is public. Store the private key as a secret (step 4), then delete
`sparkle-private-key.txt`. Keep the key in your keychain and back it up: if you lose it, installed copies can
never verify an update again.

### 2. Developer ID certificate

In Keychain Access, find **Developer ID Application: … (UFMN5LMXG2)**, expand it to include its private key,
then *Export…* as `developer-id.p12` with a password. (Create the certificate at
developer.apple.com › Certificates if you don't have one.)

### 3. App Store Connect API key, for notarization

App Store Connect › Users and Access › Integrations › **Team Keys** › add a key with the **Developer** role.
Download `AuthKey_XXXXXXXXXX.p8` (only possible once) and note the **Key ID** and the **Issuer ID**.

### 4. GitHub environment and secrets

The workflow reads its secrets from an environment named `release`. Optionally, add yourself as a required
reviewer there to approve each release.

```sh
gh api -X PUT repos/atacan/LargeText/environments/release
gh secret set DEVELOPER_ID_P12_BASE64   --env release < <(base64 -i developer-id.p12)
gh secret set DEVELOPER_ID_P12_PASSWORD --env release        # paste the .p12 password
gh secret set ASC_KEY_P8_BASE64         --env release < <(base64 -i AuthKey_XXXXXXXXXX.p8)
gh secret set ASC_KEY_ID                --env release --body XXXXXXXXXX
gh secret set ASC_ISSUER_ID             --env release --body 00000000-0000-0000-0000-000000000000
gh secret set SPARKLE_ED_PRIVATE_KEY    --env release < sparkle-private-key.txt
```

Then delete the local `.p12`, `.p8` and private key exports, or keep them only in a password manager.

### 5. Labels

```sh
gh label create release:minor --color 1D76DB --description "Release as a minor version"
gh label create release:major --color B60205 --description "Release as a major version"
gh label create skip-release  --color CCCCCC --description "Merge without releasing"
```

### 6. Public repository

Sparkle and Homebrew download without signing in, so updates and `brew install` only work while the
repository is public (it has been since the first release, 0.1.0). If it is ever made private, releases
still build, but installed copies stop receiving updates.

If you protect `main` later, the release workflow still has to push the cask commit: let the GitHub Actions
bot bypass the rule (or the ruleset), or the cask step fails after the release is already published. Fix
that kind of failure by running `scripts/release/update-cask.sh` with `VERSION` and `DMG_SHA256` and
committing the cask.

## Releasing from your Mac

For when Actions can't run. On an up-to-date `main`:

```sh
NOTARYTOOL_PROFILE=largetext scripts/release.sh --bump patch --notes '- Fixed …'
scripts/release.sh --bump minor --notes-file notes.md --dry-run   # prints the version and build only
```

It uses the Developer ID certificate in your login keychain, the Sparkle key from `generate_keys` (or
`SPARKLE_ED_KEY_FILE`), a notarytool profile (`xcrun notarytool store-credentials largetext`) and your `gh`
login. It runs the same scripts as the workflow, including the cask commit.

## When a release fails

- **Before "Publish the GitHub release"**: nothing was published. Fix the problem and re-run the workflow
  run (or merge the fix, which releases with the next version).
- **Notarization**: the step prints Apple's log. Common causes are a missing hardened runtime or an unsigned
  nested binary.
- **"the new item isn't signed"**: `SPARKLE_ED_PRIVATE_KEY` doesn't belong to `SPARKLE_PUBLIC_ED_KEY`.
- **"matches 0 signing identities"**: the `.p12` lacks the private key or has expired.
- **Cask push**: the release is out; update the cask by hand as described above.
- A failed build's DMG is attached to the workflow run as `largetext-dmg` for 7 days.
