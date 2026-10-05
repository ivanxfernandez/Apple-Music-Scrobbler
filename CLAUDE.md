# Apple Music Scrobbler

Scrobbles the Apple Music app to Last.fm and shows a Discord "Listening to" status.
Public repo: https://github.com/ivanxfernandez/Apple-Music-Scrobbler. The owner (Ivan) shares it with the community.

## Current work: macOS version

The Windows app is done and released (see CHANGELOG.md). **Next is the macOS app: read `docs/macos-plan.md` first.**
It records the decisions already made, the one open decision (code signing), and the order of work.

## Layout

- `src/AppleMusicScrobbler/`: Windows app. C# on .NET Framework 4.8 (ships with Windows, so it's a single ~100 KB exe with no dependencies). WinForms tray app.
  - `MediaReader`: Windows media controls (Apple Music packs "Artist — Album" into the artist field)
  - `PlayTracker`: scrobble rules (pure, tested). `Scrobbler`: queue + delivery
  - `LastFmClient`, `TitleCleaner`, `UpdateChecker`, `Discord/` (IPC pipe, activity builder, iTunes Search art lookup)
- `tests/AppleMusicScrobbler.Tests/`: xUnit tests. These are the behavior spec for the Mac port too.
- `macos/`: macOS app (planned, see docs/macos-plan.md)
- `.github/workflows/`: `build.yml` (every push), `release.yml` (on `v*` tags: tests, build with secrets, GitHub release)
- `tools/`: icon and README screenshot generators (Windows PowerShell)

## Commands (Windows)

```
dotnet build AppleMusicScrobbler.sln -c Release
dotnet test AppleMusicScrobbler.sln -c Release
```

`AppleMusicScrobbler.exe --dry-run` logs instead of sending to Last.fm.

## Conventions

- Keep apps dependency-free where reasonable (no NuGet runtime packages in the Windows exe).
- One feature per commit. Commit messages end with a `Co-Authored-By` line for Claude.
- Releases: bump `<Version>` in the csproj, add a CHANGELOG entry, commit, push, then `git tag vX.Y.Z` and push the tag.
  Both platforms share version numbers and one GitHub release (the Windows updater only reads `releases/latest` with `vX.Y.Z` tags).
- Build-time values: Last.fm key/secret come from the repo secrets `LASTFM_API_KEY` / `LASTFM_API_SECRET` (never commit them).
  The Discord application ID `1556532063429988354` is public and committed.
- Explain choices in plain language, and ask the owner before anything that costs money or publishes.
