# Changelog

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
