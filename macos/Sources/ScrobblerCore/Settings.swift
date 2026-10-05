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
        defaults.register(defaults: ["CheckForUpdates": true, "CleanTitles": true, "ShowOnDiscord": true])
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
    /// "Artist - Title" of the latest scrobble, shown in the menu.
    public var lastScrobbled: String {
        get { defaults.string(forKey: "LastScrobbled") ?? "" }
        set { defaults.set(newValue, forKey: "LastScrobbled") }
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
