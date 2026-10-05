<p align="center"><img src="docs/icon.png" width="96" alt=""></p>

# Apple Music Scrobbler for Windows

Scrobble the **Apple Music app for Windows** to **Last.fm**. No browser extension and no iTunes needed.

The Apple Music app on Windows 11/10 doesn't support Last.fm. This small tray app watches what Apple Music is playing (through the same Windows media controls you see in the volume flyout) and sends it to your Last.fm profile.

- **Now playing** shows up on your Last.fm profile while a song plays
- **Scrobbles** follow Last.fm's rules: songs longer than 30 seconds count once you've played half of them or 4 minutes, whichever comes first
- **Works offline**: scrobbles are saved and sent when you're back online
- **♥ Love** the current song from the tray menu
- Pause scrobbling, switch accounts, and start with Windows from the tray menu
- A single ~80 KB `.exe`. There's no installer and nothing else to download, because it uses the .NET Framework 4.8 that already comes with Windows 10/11

## Install

1. Download `AppleMusicScrobbler.exe` from [Releases](../../releases).
2. Put it somewhere permanent, for example `%LOCALAPPDATA%\Programs\AppleMusicScrobbler\`. The "Start with Windows" option points at wherever the exe is.
3. Run it. The setup window walks you through connecting your Last.fm account.

> **Windows SmartScreen** may warn about an unrecognized app because the exe isn't code-signed. Click **More info → Run anyway**, or build it yourself from source (see below).

### About the Last.fm API key

Last.fm requires each app to have an API key. Unless your copy was built with a key included (see [Building](#building)), setup asks you to make your own. It's free and takes a minute:

1. Open [last.fm/api/account/create](https://www.last.fm/api/account/create) while signed in to Last.fm.
2. Enter any application name and description, and leave **Callback URL** empty.
3. Copy the **API key** and **Shared secret** into the setup window and click **Connect**.
4. Click **Yes, allow access** on the Last.fm page that opens.

## Usage

The app lives in the system tray as a red note icon (you may need to click the **^** arrow to see it). Click it for:

| Menu item | What it does |
| --- | --- |
| *Now playing / Last scrobbled* | Status |
| ♥ Love this song on Last.fm | Loves the current track |
| Pause scrobbling | Stops sending anything (the icon turns grey) |
| Open my Last.fm profile | Opens your profile in the browser |
| Switch Last.fm account... | Reconnects, or connects a different account |
| Start with Windows | Runs automatically when you sign in |
| Open log | Shows what was sent and any errors |

## How it works

- Reads the Windows **System Media Transport Controls** session belonging to Apple Music (`AppleInc.AppleMusicWin`), polling once a second.
- Apple Music reports the artist field as `Artist — Album` and leaves the album empty. The app splits that field back into artist and album.
- Calls the [Last.fm API](https://www.last.fm/api) directly: `track.updateNowPlaying`, `track.scrobble` (in batches of up to 50) and `track.love`. Sign-in uses Last.fm's [desktop auth flow](https://www.last.fm/api/desktopauth), so the app never sees your password.

### Your data

Everything is stored in `%APPDATA%\AppleMusicScrobbler\`:

- `settings.xml`: your Last.fm username, and the session key and API secret encrypted with Windows DPAPI, so only your Windows user can read them
- `queue.xml`: scrobbles waiting to be sent
- `scrobbler.log`: activity log, capped at about 1 MB

The app talks only to `ws.audioscrobbler.com`, which is Last.fm's API.

## Known limitations

- Only the Apple Music app is supported, not iTunes or Apple Music in a browser. For the web player, use [Web Scrobbler](https://web-scrobbler.com/).
- Radio stations and other streams with no artist aren't scrobbled.
- Repeat detection depends on Apple Music reporting the playback position. If you play the same song twice in a row, it normally scrobbles twice.

## Building

Requires the [.NET SDK](https://dotnet.microsoft.com/download) (8 or later) on Windows.

```bash
dotnet build src/AppleMusicScrobbler -c Release
```

The exe is written to `src/AppleMusicScrobbler/bin/Release/net48/AppleMusicScrobbler.exe`.

To include a Last.fm API key so that users skip creating their own:

```bash
dotnet build src/AppleMusicScrobbler -c Release -p:LastFmApiKey=YOUR_KEY -p:LastFmApiSecret=YOUR_SECRET
```

Keep the key out of the repository and pass it only when building a release.

Useful while developing:

- `AppleMusicScrobbler.exe --dry-run` logs what it would send, without contacting Last.fm.
- `tools/make-icon.ps1` regenerates `app.ico` from `IconFactory.cs`.

## Uninstall

Untick **Start with Windows** in the tray menu, then choose **Quit**. Delete the exe and the `%APPDATA%\AppleMusicScrobbler` folder.

## License

[MIT](LICENSE)

*Not affiliated with Apple or Last.fm.*
