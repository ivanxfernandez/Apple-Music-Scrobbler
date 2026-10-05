# Contributing

Thanks for helping! Bug reports and ideas are welcome as [issues](../../issues/new/choose). The app's *Report a problem* menu item fills in the details for you.

## Translating the app

The app follows the system language. English is written in the code, and each other language is one table per platform:

| Platform | File | Placeholders |
| --- | --- | --- |
| Windows | [`src/AppleMusicScrobbler/Localization.cs`](src/AppleMusicScrobbler/Localization.cs) | `{0}`, `{1}`… |
| Mac | [`macos/Sources/ScrobblerCore/Localization.swift`](macos/Sources/ScrobblerCore/Localization.swift) | `%@` (filled in order) |

To add a language, for example French:

1. Copy the `Spanish` table in each file, name it `French`, and translate the values. Keep the English keys exactly as they are.
2. Return it for the language code in `Table` (`"fr"`).
3. Run the tests (below). They list any text that has no translation, any translation whose placeholders don't match the English, and any entry the app no longer uses.
4. Preview it with `--language fr`:
   - Windows: `AppleMusicScrobbler.exe --language fr`
   - Mac: `open "/Applications/Apple Music Scrobbler.app" --args --language fr` (quit the app first)

Keep translations short enough for a menu. The log and the Discord status stay in English on purpose: logs are for bug reports, and the Discord status is read by your friends.

Improvements to the Spanish are welcome too.

## Building and testing

**Windows** needs the [.NET SDK](https://dotnet.microsoft.com/download) 8 or later:

```
dotnet build AppleMusicScrobbler.sln -c Release
dotnet test AppleMusicScrobbler.sln -c Release
```

**Mac** needs the Xcode Command Line Tools (`xcode-select --install`), not full Xcode:

```
cd macos
./test.sh
./build-app.sh
```

`./test.sh` runs `swift test`, retrying a Command Line Tools glitch that sometimes fails to load the test macros.

Both apps take `--dry-run` (log instead of sending to Last.fm) and `--pretend-version 1.0.0` (offer the latest release as an update, to test the updater).

## Pull requests

- Work on a branch and open a pull request against `main`. GitHub Actions builds and tests both apps on every pull request, and the *Screenshots* workflow photographs the Windows app in light and dark mode.
- Keep the scrobbling rules the same on both platforms. They're tested on both (`tests/` and `macos/Tests/`), so a change to one usually needs the same change and test on the other.
- Keep the apps dependency-free: no NuGet runtime packages in the Windows exe, no Swift packages in the Mac app.
- New text shown to users goes through `L("…")` and needs a Spanish entry; the tests will tell you.
