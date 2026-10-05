# macOS version: plan

Status: **released in v1.3.0** (unsigned). See *Verified on the Mac*. Written from the Windows side on 2026-10-04 so the work can continue on a Mac.
Facts marked *(verify)* come from general knowledge and must be checked on a real Mac before relying on them.

## Goal

A native macOS menu-bar app with the same features as the Windows app (see `CHANGELOG.md`):
Last.fm now playing + scrobbling with an offline queue, love, pause, title cleanup,
Discord "Listening to" status, update notifications, start at login.
Same repo, same version numbers, one GitHub release containing both the Windows exe and the Mac app.

## Decisions already made

| Topic | Decision | Why |
| --- | --- | --- |
| Language/UI | Swift, agent app (`LSUIElement`, no Dock icon). Menu bar: AppKit `NSStatusItem` + `NSMenu` (not SwiftUI `MenuBarExtra`: a plain menu matches the Windows tray menu 1:1 and updates its text every second cheaply). Setup window: SwiftUI | Native, small, no runtime to install |
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
| `MediaReader` reads the Windows media controls | Observe the distributed notification **`com.apple.Music.playerInfo`** (`DistributedNotificationCenter`). Verified keys and behavior: see *Verified on the Mac* below. Needs no permission. Do **not** use the private MediaRemote framework, which is locked down since macOS 15.4. |
| Playback position (for repeat/seek detection) | Not in the notification, and Music posts **nothing** when a song restarts on Repeat One (verified). Options: (a) count listening time locally and treat each full duration of continuous play as a new listen; (b) poll `player position` through AppleScript/ScriptingBridge once a second while playing, which shows one Automation prompt (`NSAppleEventsUsageDescription`) and lets `PlayTracker` port 1:1. **Decided: (b)**, with (a) as the fallback when the prompt is denied: a local play clock that wraps at the duration, so `PlayTracker`'s unchanged repeat rule still fires. Run the AppleScript off the main thread with `with timeout of 2 seconds`, only when Music is running (`NSRunningApplication`), and trigger the prompt from a step in the setup window. |
| `PlayTracker` (scrobble rules) | Port 1:1. The C# file and `tests/AppleMusicScrobbler.Tests/PlayTrackerTests.cs` are the spec. Port the tests too. |
| `TitleCleaner` | Port the regexes 1:1 (`NSRegularExpression` / Swift `Regex`), with its tests (`NameTests.cs`). |
| `LastFmClient` | `URLSession`. MD5 signing with `CryptoKit.Insecure.MD5`, same rules (sorted params + secret, UTF-8). Same desktop auth flow (`auth.getToken` → browser → poll `auth.getSession`). XML responses. |
| `Settings` (DPAPI) | `UserDefaults` for options; session key and any user-supplied API secret in a `0600` file in `~/Library/Application Support/AppleMusicScrobbler/` (not Keychain: unsigned builds change signature every release, which would bring back a Keychain prompt after each update). |
| Offline queue (`queue.xml`) | JSON file in `~/Library/Application Support/AppleMusicScrobbler/`. |
| Log | `~/Library/Logs/AppleMusicScrobbler/scrobbler.log` (Console.app can open it). |
| `Startup` (Run registry key) | `SMAppService.mainApp.register()`. |
| `DiscordIpc` (named pipe) | Unix domain socket `$TMPDIR/discord-ipc-0`…`9` (`NSTemporaryDirectory()`), verified. Same frames: `[int32 LE opcode][int32 LE length][JSON]`, same handshake and `SET_ACTIVITY` payload. Port `ActivityBuilder` + tests. |
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

## Verified on the Mac (2026-10-04, macOS 27.0.1, Apple Silicon)

Logged with a small `DistributedNotificationCenter` listener and scripted playback.

- **Notification:** `com.apple.Music.playerInfo`. Music also posts an identical `com.apple.iTunes.playerInfo` for every event: subscribe to only one, or every event is counted twice.
- **Keys:** `Name`, `Artist`, `Album`, `Composer`, `Genre`, `Total Time` (ms, Number), `Player State` (`Playing`/`Paused`/`Stopped`), `PersistentID` (per track, signed Int64), `Library PersistentID` (same for every track, so it's the library, not the song). No `Album Artist` key was seen.
- **Artist and Album are separate, clean fields.** No "Artist — Album" packing as on Windows. Album names still carry "(Deluxe Edition)" and titles "[2022 Remaster]", so `TitleCleaner` is still needed.
- **State-only events:** `Stopped` (and the first `Paused` on launch) can arrive with no song fields at all. `Stopped` between tracks is not reliable: some track changes post it, some don't.
- **`Total Time` can change mid-track** (142000 → 142506, 192043 → 191999 → 192000). Never treat a duration change as a new song; key plays on `PersistentID`.
- **No event** for scripted seeks (`set player position`) or for a **Repeat One restart**. Changing the repeat setting **does** re-post the same `Playing` payload. Pause/resume and track changes post as expected.
- **Position:** only via AppleScript `player position` (seconds, real). `tell application "Music"` launches Music if it isn't running, so check `NSRunningApplication` first.
- **Automation permission survives unsigned updates:** after allowing access, rebuilding the ad-hoc signed app with a code change (new CDHash) and relaunching it from the same place kept the permission (macOS 27). Also verified with the v1.3.0 release: a browser-downloaded (quarantined) copy replacing a local build kept the permission, the Last.fm login and the settings. Gatekeeper behaved as the README describes (blocked, then *Privacy & Security › Open Anyway* with the user's password).
- **Toolchain:** Command Line Tools only (no Xcode) build Swift packages and run **Swift Testing** tests, including `CryptoKit` MD5. **XCTest is not available** without Xcode, so write all tests with Swift Testing.

## What to check on the Mac before starting

- `sw_vers` (macOS version), `uname -m` (arm64 = Apple Silicon)
- `xcode-select -p` and `swift --version` (full Xcode recommended for XCTest/Swift Testing)
- Apple Music app signed in and playing; Discord desktop app installed (for the Discord part)
