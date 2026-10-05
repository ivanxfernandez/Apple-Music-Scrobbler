import Foundation

/// Facts about this build. Build-time values (API key, repo, Discord ID) are written into the
/// app's Info.plist by build-app.sh; a plain `swift build` has none of them.
public enum AppInfo {
    public static let name = "Apple Music Scrobbler"

    public static var version: String { info("CFBundleShortVersionString").isEmpty ? "0.0.0" : info("CFBundleShortVersionString") }

    /// API key compiled in by the release build, or empty.
    public static var builtInApiKey: String { info("LastFmApiKey") }
    public static var builtInApiSecret: String { info("LastFmApiSecret") }

    /// "owner/repo" this app was released from (set by the release workflow), or empty for local builds.
    public static var gitHubRepo: String { info("GitHubRepo") }
    /// Discord application ID used for the "Listening to" status, or empty to disable it.
    public static var discordClientId: String { info("DiscordClientId") }

    public static var repoUrl: String { gitHubRepo.isEmpty ? "" : "https://github.com/" + gitHubRepo }

    /// ~/Library/Application Support/AppleMusicScrobbler
    public static var dataFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppleMusicScrobbler", isDirectory: true)
    }

    /// ~/Library/Logs/AppleMusicScrobbler (Console.app shows it under Log Reports)
    public static var logFolder: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/AppleMusicScrobbler", isDirectory: true)
    }

    private static func info(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
    }
}
