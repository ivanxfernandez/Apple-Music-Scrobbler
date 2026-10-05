# macOS version: plan

Status: **not started**. Written from the Windows side on 2026-10-04 so the work can continue on a Mac.
Facts marked *(verify)* come from general knowledge and must be checked on a real Mac before relying on them.

## Goal

A native macOS menu-bar app with the same features as the Windows app (see `CHANGELOG.md`):
Last.fm now playing + scrobbling with an offline queue, love, pause, title cleanup,
Discord "Listening to" status, update notifications, start at login.
Same repo, same version numbers, one GitHub release containing both the Windows exe and the Mac app.

## Decisions already made

| Topic | Decision | Why |
| --- | --- | --- |
| Language/UI | Swift + SwiftUI `MenuBarExtra`, agent app (`LSUIElement`, no Dock icon) | Native, small, no runtime to install |
| Minimum macOS | 13 Ventura | `MenuBarExtra` and `SMAppService` (start at login) need 13+ |
| Repo layout | New `macos/` folder; Windows stays in `src/` and `tests/` | Don't break the Windows build, workflows or README links |
| Build | Swift Package Manager (`macos/Package.swift`) plus a script that wraps the binary into `Apple Music Scrobbler.app` (Info.plist, icon) | Builds from the command line, works in CI and for an agent without the Xcode GUI |
| Sandbox | **Off** (not App Store) | Discord's IPC socket and Music's notifications aren't reachable from the sandbox |
| Versions/releases | Shared `vX.Y.Z` tags; the Release workflow gets a `macos-latest` job that attaches a `.zip` of the app to the **same** release | The Windows updater reads `releases/latest` and only understands `vX.Y.Z` tags, so a separate `macos-v…` release would hide Windows updates |
| Last.fm API key | The same key, from the same repository secrets, baked in at build time | Users just click Connect |
| Discord app | Same application ID `1556532063429988354` | Same "Listening to" name and art assets |

## Open decision (ask Ivan)

**Code signing.** Without an Apple Developer Program membership ($99/year), downloaded apps are blocked by Gatekeeper.
On macOS 15+ users must open *System Settings › Privacy & Security › Open Anyway*. Right-click › Open no longer works.
With a membership: Developer ID signing + notarization in CI, and the app opens normally.
Both work. The README must explain the unsigned route if that's the choice.

## How each piece maps from Windows

| Windows (C#) | macOS (Swift) |
| --- | --- |
| `MediaReader` reads the Windows media controls | Observe the distributed notification **`com.apple.Music.playerInfo`** (`DistributedNotificationCenter`). userInfo keys *(verify)*: `Name`, `Artist`, `Album`, `Album Artist`, `Total Time` (ms), `Player State` (`Playing`/`Paused`/`Stopped`), `PersistentID`. Needs no permission. Check whether Apple Music on Mac also packs `Artist — Album` into one field (probably not). Do **not** use the private MediaRemote framework, which is locked down since macOS 15.4. |
| Playback position (for repeat/seek detection) | Not in the notification. Options: (a) count listening time locally like `PlayTracker` already does, and accept weaker repeat detection; (b) read `player position` through ScriptingBridge/AppleScript, which shows an Automation permission prompt (`NSAppleEventsUsageDescription`). Start with (a), and test whether Music re-posts `playerInfo` when a song repeats. |
| `PlayTracker` (scrobble rules) | Port 1:1. The C# file and `tests/AppleMusicScrobbler.Tests/PlayTrackerTests.cs` are the spec. Port the tests too. |
| `TitleCleaner` | Port the regexes 1:1 (`NSRegularExpression` / Swift `Regex`), with its tests (`NameTests.cs`). |
| `LastFmClient` | `URLSession`. MD5 signing with `CryptoKit.Insecure.MD5`, same rules (sorted params + secret, UTF-8). Same desktop auth flow (`auth.getToken` → browser → poll `auth.getSession`). XML responses. |
| `Settings` (DPAPI) | `UserDefaults` for options; **Keychain** for the session key and any user-supplied API secret. |
| Offline queue (`queue.xml`) | JSON file in `~/Library/Application Support/AppleMusicScrobbler/`. |
| Log | `~/Library/Logs/AppleMusicScrobbler/scrobbler.log` (Console.app can open it). |
| `Startup` (Run registry key) | `SMAppService.mainApp.register()`. |
| `DiscordIpc` (named pipe) | Unix domain socket `$TMPDIR/discord-ipc-0`…`9` (`NSTemporaryDirectory()`) *(verify)*. Same frames: `[int32 LE opcode][int32 LE length][JSON]`, same handshake and `SET_ACTIVITY` payload. Port `ActivityBuilder` + tests. |
| `AppleMusicLinks` (iTunes Search API) | Port 1:1 incl. `BestMatch`/`AlbumMatch` and tests. |
| `UpdateChecker` | Port 1:1; download asset = the `.zip`. |
| Tray icon + menu | `MenuBarExtra` with an SF Symbol (e.g. `music.note`) as a template image, so it follows light/dark mode. Same menu items and Options submenu. |
| `SetupForm` | SwiftUI window, same text and flow. Hidden when the API key is baked in, except for the Connect step. |

## Suggested order of work

1. On the Mac: confirm the `com.apple.Music.playerInfo` notification and its keys with a tiny script that logs it (play, pause, skip, repeat a song).
2. `macos/Package.swift` with a library target (`ScrobblerCore`: tracker, cleaner, Last.fm, Discord, links, updater: no UI) + executable target (menu-bar app) + test target. Port the tests first.
3. Menu-bar app: read Music → PlayTracker → Last.fm, with the setup window. Use it daily for a bit.
4. Discord status, update checks, start at login.
5. `macos/build-app.sh` (bundle + icon from `docs/logo-1024.png` via `iconutil`), then the CI job in `release.yml` + a `macos` build job in `build.yml`.
6. README: a macOS section (install, Gatekeeper note). CHANGELOG, release.

## What to check on the Mac before starting

- `sw_vers` (macOS version), `uname -m` (arm64 = Apple Silicon)
- `xcode-select -p` and `swift --version` (full Xcode recommended for XCTest/Swift Testing)
- Apple Music app signed in and playing; Discord desktop app installed (for the Discord part)
