import Foundation

/// Options live in UserDefaults. The Last.fm session key and a user-supplied API secret live in a
/// file only this user can read (not the Keychain: unsigned builds get a new code signature with
/// every release, and the Keychain would then ask for the user's password after each update).
public final class Settings {
    private let defaults: UserDefaults
    private let secretsURL: URL
    private var secrets: [String: String]

    public init(defaults: UserDefaults = .standard, folder: URL = AppInfo.dataFolder) {
        self.defaults = defaults
        secretsURL = folder.appendingPathComponent("secrets.json")
        secrets = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: secretsURL))) ?? [:]
        defaults.register(defaults: ["CheckForUpdates": true, "CleanTitles": true, "ShowOnDiscord": true, "MainArtistOnly": false, "CatchUp": false, "NowPlayingNotification": false])
    }

    /// User-supplied API key; empty means use the one built into the app.
    public var apiKey: String {
        get { defaults.string(forKey: "ApiKey") ?? "" }
        set { defaults.set(newValue, forKey: "ApiKey") }
    }
    public var username: String {
        get { defaults.string(forKey: "Username") ?? "" }
        set { defaults.set(newValue, forKey: "Username") }
    }
    public var paused: Bool {
        get { defaults.bool(forKey: "Paused") }
        set { defaults.set(newValue, forKey: "Paused") }
    }
    public var checkForUpdates: Bool {
        get { defaults.bool(forKey: "CheckForUpdates") }
        set { defaults.set(newValue, forKey: "CheckForUpdates") }
    }
    /// Remove "Remaster", "Deluxe Edition", "- Single" etc. from titles (see TitleCleaner).
    public var cleanTitles: Bool {
        get { defaults.bool(forKey: "CleanTitles") }
        set { defaults.set(newValue, forKey: "CleanTitles") }
    }
    /// Scrobble collaborations ("Joji & BENEE") as their first artist (see MainArtist).
    public var mainArtistOnly: Bool {
        get { defaults.bool(forKey: "MainArtistOnly") }
        set { defaults.set(newValue, forKey: "MainArtistOnly") }
    }
    /// Show "Listening to" with the current song on Discord (when Discord is running).
    public var showOnDiscord: Bool {
        get { defaults.bool(forKey: "ShowOnDiscord") }
        set { defaults.set(newValue, forKey: "ShowOnDiscord") }
    }
    /// Last version we showed an update notification for, so it's only shown once.
    public var updateNotifiedFor: String {
        get { defaults.string(forKey: "UpdateNotifiedFor") ?? "" }
        set { defaults.set(newValue, forKey: "UpdateNotifiedFor") }
    }
    /// Version that ran last time, to say "Updated to …" once after an update.
    public var lastRunVersion: String {
        get { defaults.string(forKey: "LastRunVersion") ?? "" }
        set { defaults.set(newValue, forKey: "LastRunVersion") }
    }
    /// "Artist - Title" of the latest scrobble, shown in the menu.
    public var lastScrobbled: String {
        get { defaults.string(forKey: "LastScrobbled") ?? "" }
        set { defaults.set(newValue, forKey: "LastScrobbled") }
    }

    /// The keyboard shortcut that loves the current song from anywhere ("off", or a LoveShortcut raw value).
    public var loveShortcut: String {
        get { defaults.string(forKey: "LoveShortcutKeys") ?? "" }
        set { defaults.set(newValue, forKey: "LoveShortcutKeys") }
    }
    /// A notification with the song and album art when a song starts.
    public var nowPlayingNotification: Bool {
        get { defaults.bool(forKey: "NowPlayingNotification") }
        set { defaults.set(newValue, forKey: "NowPlayingNotification") }
    }
    /// Scrobble plays from other devices found in Music's history (Mac, see CatchUp).
    public var catchUp: Bool {
        get { defaults.bool(forKey: "CatchUp") }
        set { defaults.set(newValue, forKey: "CatchUp") }
    }
    /// Plays before this aren't caught up (set to a day before the option was turned on).
    public var catchUpSince: Date {
        get { defaults.object(forKey: "CatchUpSince") as? Date ?? Date() }
        set { defaults.set(newValue, forKey: "CatchUpSince") }
    }

    /// Artists not to scrobble or show on Discord (see IgnoreList).
    public var ignoredArtists: [String] {
        get { defaults.stringArray(forKey: "IgnoredArtists") ?? [] }
        set { defaults.set(newValue, forKey: "IgnoredArtists") }
    }

    /// Latest accepted scrobbles, newest first (see RecentScrobbles).
    public var recentScrobbles: [RecentScrobble] {
        get { (defaults.data(forKey: "RecentScrobbles")).flatMap { try? JSONDecoder().decode([RecentScrobble].self, from: $0) } ?? [] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "RecentScrobbles") }
    }

    public var apiSecret: String {
        get { secrets["ApiSecret"] ?? "" }
        set { secrets["ApiSecret"] = newValue }
    }
    public var sessionKey: String {
        get { secrets["SessionKey"] ?? "" }
        set { secrets["SessionKey"] = newValue }
    }

    public var effectiveApiKey: String { apiKey.isEmpty ? AppInfo.builtInApiKey : apiKey }
    public var effectiveApiSecret: String { apiKey.isEmpty ? AppInfo.builtInApiSecret : apiSecret }
    public var isConnected: Bool { !sessionKey.isEmpty && !effectiveApiKey.isEmpty }

    /// Writes the secrets file (options are saved by UserDefaults as they change).
    public func save() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: secretsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(secrets)
        let temp = secretsURL.appendingPathExtension("tmp")
        fm.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600])
        if fm.fileExists(atPath: secretsURL.path) {
            _ = try fm.replaceItemAt(secretsURL, withItemAt: temp)
        } else {
            try fm.moveItem(at: temp, to: secretsURL)
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretsURL.path)
    }
}
