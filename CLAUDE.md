# Apple Music Scrobbler

Scrobbles the Apple Music app (Windows and Mac) to Last.fm and shows a Discord "Listening to" status.
Public repo: https://github.com/ivanxfernandez/Apple-Music-Scrobbler. The owner (Ivan) shares it with the community.

## Status

Both platforms released together since 1.3.0 (latest: see CHANGELOG.md), in daily use on Ivan's Mac mini, MacBook and Windows PC.
The Mac app is deliberately unsigned (no paid Apple account; the README explains Open Anyway). `docs/macos-plan.md` records the Mac
decisions and what was verified about the Music app. An iPhone app was considered and set aside: Mac catch-up covers it while the Mac is on.
Windows UI can't be seen from the Mac: the Screenshots workflow photographs it (light/dark, en/es) on every dev push that touches `src/`.

## Layout

- `src/AppleMusicScrobbler/`: Windows app. C# on .NET Framework 4.8 (ships with Windows, so it's a single ~100 KB exe with no dependencies). WinForms tray app.
  - `MediaReader`: Windows media controls (Apple Music packs "Artist — Album" into the artist field)
  - `PlayTracker`: scrobble rules (pure, tested). `Scrobbler`: queue + delivery
  - `LastFmClient`, `TitleCleaner`, `UpdateChecker`, `Discord/` (IPC pipe, activity builder, iTunes Search art lookup)
- `tests/AppleMusicScrobbler.Tests/`: xUnit tests. These are the behavior spec for the Mac port too.
- `macos/`: macOS app, a Swift package (Swift 6 toolchain, Swift 5 language mode, macOS 13+).
  - `Sources/ScrobblerCore/`: port of the Windows logic (PlayTracker, TitleCleaner, LastFmClient, Scrobbler, UpdateChecker, Discord/). Keep it in step with the C# code.
  - `Sources/AppleMusicScrobbler/`: menu bar app. `MusicReader` (playerInfo notification + AppleScript `player position`, wrapping clock as fallback), `MenuBarApp` (NSStatusItem menu), `SetupWindow` (SwiftUI)
  - `Tests/ScrobblerCoreTests/`: the Windows tests ported to Swift Testing
  - `build-app.sh`: wraps the binary into `build/Apple Music Scrobbler.app` + zip (Info.plist values, icon, ad-hoc signature)
- `.github/workflows/`: `build.yml` (every push), `release.yml` (on `v*` tags: tests, build with secrets, GitHub release)
- `tools/`: icon and README screenshot generators (Windows PowerShell)

## Commands (Windows)

```
dotnet build AppleMusicScrobbler.sln -c Release
dotnet test AppleMusicScrobbler.sln -c Release
```

`AppleMusicScrobbler.exe --dry-run` logs instead of sending to Last.fm.

## Commands (Mac, in `macos/`)

```
./test.sh                 # swift test, retrying the flaky TestingMacros load error
./build-app.sh            # [version]; env LASTFM_API_KEY, LASTFM_API_SECRET, GITHUB_REPO, UNIVERSAL=1
open "build/Apple Music Scrobbler.app" --args --dry-run
```

- Only the Command Line Tools are installed (no Xcode), so tests must use Swift Testing, not XCTest.
- Plain `swift test` often fails with "plugin for module 'TestingMacros' not found" after a test file changes (a Command Line Tools glitch, not a code problem); `./test.sh` retries it.
- Test the updater with `--pretend-version 1.0.0` on a build that has `GITHUB_REPO` set: it offers the latest release as an update.
- No C# compiler on the Mac: push to the `dev` branch (draft PR) and let GitHub Actions build and test the Windows code.
- Log: `~/Library/Logs/AppleMusicScrobbler/scrobbler.log`. Ivan's installed copy is `/Applications/Apple Music Scrobbler.app`.

## Conventions

- Keep apps dependency-free where reasonable (no NuGet runtime packages in the Windows exe).
- One feature per commit. Commit messages end with a `Co-Authored-By` line for Claude.
- Releases: bump `<Version>` in the csproj (the Mac version comes from the tag, or the newest CHANGELOG heading for local builds), add a CHANGELOG entry, commit, push, then `git tag vX.Y.Z` and push the tag.
  Both platforms share version numbers and one GitHub release (the Windows updater only reads `releases/latest` with `vX.Y.Z` tags).
- Build-time values: Last.fm key/secret come from the repo secrets `LASTFM_API_KEY` / `LASTFM_API_SECRET` (never commit them).
  The Discord application ID `1556532063429988354` is public and committed.
- User-facing text goes through `L("…")` (Windows: `{0}` placeholders, Mac: `%@`) and needs an entry in both Spanish tables; the tests fail on missing or unused entries. Log messages and the Discord activity stay in English.
- Explain choices in plain language, and ask the owner before anything that costs money or publishes.
