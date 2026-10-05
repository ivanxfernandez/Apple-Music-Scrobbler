// swift-tools-version:6.0
import PackageDescription

// Builds with the Command Line Tools alone (no Xcode). Tests use Swift Testing, because XCTest needs Xcode.
// The .app bundle is assembled by build-app.sh.
let package = Package(
    name: "AppleMusicScrobbler",
    platforms: [.macOS(.v13)],
    targets: [
        // Everything that isn't UI: scrobble rules, Last.fm, Discord, update check. Unit-tested.
        .target(name: "ScrobblerCore"),
        // The menu bar app.
        .executableTarget(name: "AppleMusicScrobbler", dependencies: ["ScrobblerCore"]),
        .testTarget(name: "ScrobblerCoreTests", dependencies: ["ScrobblerCore"]),
    ],
    swiftLanguageModes: [.v5]
)
