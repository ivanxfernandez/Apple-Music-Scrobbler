# Changelog

## 1.5.0

- **Spanish**: the app is in Spanish when Windows or macOS is set to Spanish. Translations live in one table per platform (`src/AppleMusicScrobbler/Localization.cs`, `macos/Sources/ScrobblerCore/Localization.swift`), so other languages are easy to add.
- **Ignore list**: *Don't scrobble [artist]* in the menu stops sending that artist to Last.fm and Discord (collaborations they lead too). *Options › Ignored artists* lists them; click one to undo.
- **Mac: catch up on plays from other devices** (*Options*, off by default): songs from your library that you played on your iPhone or iPad are scrobbled from Music's play history, which iCloud syncs to the Mac within seconds. Plays already on Last.fm are skipped. If you use *Scan* in the Last.fm iPhone app, use one or the other.

## 1.4.0

- **One-click updates**: when a new version is out, click the notification or the *Update available* menu item and the app installs it and restarts. It checks the download against the SHA-256 GitHub publishes before installing, and opens the download page instead if anything doesn't check out. This works from 1.4.0 on; to get 1.4.0 itself, update by hand once.
- **Recent scrobbles** submenu: the last 10 songs sent to Last.fm (click one to open it there), anything still waiting to be sent, and a **Send now** button.
- **Scrobble only the main artist of collaborations** (*Options*, off by default): *"Joji & BENEE"* is scrobbled as *"Joji"*. Bands like *Simon & Garfunkel* are left alone; Last.fm's own listener counts tell the two apart.
- **Report a problem** in the menu opens a GitHub issue with your app version, system and recent log lines filled in, and the repository has issue forms for problems and ideas.
- An *"Updated to …"* notification after an update.
- Mac screenshots in the README.

## 1.3.0

- **Mac version**: a menu bar app for the Music app on macOS 13 or newer (Apple Silicon and Intel), with the same features as on Windows: now playing, scrobbling with an offline queue, love, pause, title cleanup, Discord status, update notifications and start at login. It asks once for access to Music so songs played on repeat are scrobbled each time. Download `AppleMusicScrobbler-macOS.zip` from the release; see the README for the first launch.
- Windows: no changes in this version.

## 1.2.0

- **Discord status**: shows *Listening to Apple Music* on your Discord profile with the song (linked to Apple Music), artist, album art, a progress bar, and *Listen on Apple Music* / *Last.fm profile* buttons. It's hidden while paused, reconnects automatically when Discord starts, and can be turned off in *Options*.

## 1.1.0

- **Title cleanup**: "Remaster", "Deluxe Edition", "- Single" and similar tags are removed before scrobbling, so plays land on the normal Last.fm track and album pages. Turn it off with *Options › Clean up titles*.
- **Update notifications**: the app checks for new releases once a day and shows a notification and an *Update available* menu item when one is out.
- The tray menu has an *Options* submenu and an *About* item.
- "Last scrobbled" is remembered after a restart.
- Releases are built and published automatically by GitHub Actions, and the code has unit tests.

## 1.0.0

- First release: now playing, scrobbling with an offline queue, love, pause, start with Windows.
