# winget

The Windows app is published to [winget](https://learn.microsoft.com/windows/package-manager/) as `ivanxfernandez.AppleMusicScrobbler`, so people can install it with:

```
winget install ivanxfernandez.AppleMusicScrobbler
```

It's a *portable* package: winget downloads the exe to its own folder and adds an `AppleMusicScrobbler` command. Run that once; after that the app lives in the tray and can start with Windows. It still updates itself (*Update available* in the menu); `winget upgrade` also works, it just downloads the release again.

## Publishing a new version

1. Release the version on GitHub first (tag `vX.Y.Z`).
2. `packaging/winget/make-manifests.sh X.Y.Z` writes the three manifest files with the exe's URL and SHA-256 from the release.
3. Copy `manifests/i/ivanxfernandez/AppleMusicScrobbler/X.Y.Z/` into a fork of [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs) at the same path and open a pull request. Their bot validates it; a first package also gets a human review, which can take a few days.

The generated folders aren't committed here: they're rebuilt from the release each time.
