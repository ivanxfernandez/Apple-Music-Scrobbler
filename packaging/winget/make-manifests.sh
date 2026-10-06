#!/bin/bash
# Writes the winget manifests for a published release into manifests/i/ivanxfernandez/AppleMusicScrobbler/<version>/,
# laid out like microsoft/winget-pkgs, using the exe's download URL and SHA-256 from the GitHub release.
#
#   packaging/winget/make-manifests.sh 1.7.0
#
# Submitting them is a pull request to https://github.com/microsoft/winget-pkgs (see README.md here).
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${1:?usage: make-manifests.sh <version>}"
VERSION="${VERSION#v}"
REPO="ivanxfernandez/Apple-Music-Scrobbler"
ID="ivanxfernandez.AppleMusicScrobbler"
# winget-pkgs asks for the newest format; WINGET_SCHEMA=1.10.0 for older winget clients (the CI runner).
SCHEMA="${WINGET_SCHEMA:-1.12.0}"

read -r URL SHA DATE < <(curl -fsSL "https://api.github.com/repos/$REPO/releases/tags/v$VERSION" | python3 -c '
import json, sys
release = json.load(sys.stdin)
asset = next(a for a in release["assets"] if a["name"] == "AppleMusicScrobbler.exe")
assert asset["digest"].startswith("sha256:"), "no SHA-256 digest on the release asset"
print(asset["browser_download_url"], asset["digest"][7:].upper(), release["published_at"][:10])
')

OUT="manifests/i/ivanxfernandez/AppleMusicScrobbler/$VERSION"
mkdir -p "$OUT"

cat > "$OUT/$ID.yaml" <<YAML
# yaml-language-server: \$schema=https://aka.ms/winget-manifest.version.$SCHEMA.schema.json

PackageIdentifier: $ID
PackageVersion: $VERSION
DefaultLocale: en-US
ManifestType: version
ManifestVersion: $SCHEMA
YAML

cat > "$OUT/$ID.installer.yaml" <<YAML
# yaml-language-server: \$schema=https://aka.ms/winget-manifest.installer.$SCHEMA.schema.json

PackageIdentifier: $ID
PackageVersion: $VERSION
InstallerType: portable
Commands:
- AppleMusicScrobbler
MinimumOSVersion: 10.0.0.0
ReleaseDate: $DATE
Installers:
- Architecture: neutral
  InstallerUrl: $URL
  InstallerSha256: $SHA
ManifestType: installer
ManifestVersion: $SCHEMA
YAML

cat > "$OUT/$ID.locale.en-US.yaml" <<YAML
# yaml-language-server: \$schema=https://aka.ms/winget-manifest.defaultLocale.$SCHEMA.schema.json

PackageIdentifier: $ID
PackageVersion: $VERSION
PackageLocale: en-US
Publisher: Ivan Fernandez
PublisherUrl: https://github.com/ivanxfernandez
PublisherSupportUrl: https://github.com/$REPO/issues
PackageName: Apple Music Scrobbler
PackageUrl: https://github.com/$REPO
License: MIT
LicenseUrl: https://github.com/$REPO/blob/HEAD/LICENSE
Copyright: Copyright (c) 2026 Ivan Fernandez
ShortDescription: Scrobbles the Apple Music app for Windows to Last.fm, with a Discord "Listening to" status.
Description: |-
  A small tray app that watches what the Apple Music app for Windows is playing and sends it to your Last.fm profile:
  now playing, scrobbles with an offline queue, love, title cleanup, a Discord status, and one-click updates.
  Not affiliated with Apple or Last.fm.
Moniker: apple-music-scrobbler
Tags:
- apple-music
- discord
- last-fm
- lastfm
- music
- scrobbler
InstallationNotes: Run "AppleMusicScrobbler" once (from a terminal or the Run box) to start it. It then lives in the system tray and can start with Windows (Options).
ReleaseNotesUrl: https://github.com/$REPO/releases/tag/v$VERSION
ManifestType: defaultLocale
ManifestVersion: $SCHEMA
YAML

echo "Wrote $OUT"
