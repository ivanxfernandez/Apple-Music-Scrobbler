import Foundation

public struct TrackLinks: Equatable {
    public var artworkUrl: String?
    public var trackUrl: String?
    public var albumUrl: String?
    public var artistUrl: String?

    public init(artworkUrl: String? = nil, trackUrl: String? = nil, albumUrl: String? = nil, artistUrl: String? = nil) {
        self.artworkUrl = artworkUrl
        self.trackUrl = trackUrl
        self.albumUrl = albumUrl
        self.artistUrl = artistUrl
    }
}

/// Builds the Discord activity JSON. Pure functions, unit-tested.
public enum ActivityBuilder {
    /// Art asset key shown when no album art was found (the app icon, uploaded as "logo" in the Discord app).
    public static let fallbackImage = "logo"

    /// A playing track as a "Listening to" activity with artwork, progress bar and links.
    public static func build(_ np: NowPlaying, links: TrackLinks?, startMs: Int64, lastFmUser: String?) -> String {
        var activity: [String: Any] = [
            "type": 2,                 // Listening
            "status_display_type": 1,  // member list shows "Listening to <artist>"
            "details": text(np.title),
            "state": text(np.artist),
        ]
        if let url = links?.trackUrl, isUrl(url) { activity["details_url"] = url }
        if let url = links?.artistUrl, isUrl(url) { activity["state_url"] = url }

        var timestamps: [String: Any] = ["start": startMs]
        if np.duration > 0 { timestamps["end"] = startMs + Int64(np.duration) * 1000 }
        activity["timestamps"] = timestamps

        var assets: [String: Any] = [
            "large_image": links?.artworkUrl.flatMap { isUrl($0) ? $0 : nil } ?? fallbackImage,
            "large_text": text(np.album.isEmpty ? np.title : np.album),
        ]
        if let url = links?.albumUrl, isUrl(url) { assets["large_url"] = url }
        activity["assets"] = assets

        var buttons: [[String: String]] = []
        if let url = links?.trackUrl, isUrl(url) { buttons.append(["label": "Listen on Apple Music", "url": url]) }
        if let user = lastFmUser, !user.isEmpty { buttons.append(["label": "Last.fm profile", "url": "https://www.last.fm/user/" + Http.escape(user)]) }
        if !buttons.isEmpty { activity["buttons"] = buttons }

        return json(activity)
    }

    /// Discord requires 2-128 characters (counted in UTF-16 units, like JavaScript).
    public static func text(_ s: String?) -> String {
        var s = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.utf16.count > 128 {
            var cut = ""
            for c in s {
                if cut.utf16.count + c.utf16.count > 127 { break }
                cut.append(c)
            }
            s = cut + "…"
        }
        while s.utf16.count < 2 { s += "\u{200B}" } // zero-width space
        return s
    }

    /// A new track, or the playback position jumped (seek, restart) by more than 3 seconds.
    public static func needsUpdate(shownKey: String?, shownStartMs: Int64, key: String, startMs: Int64) -> Bool {
        shownKey != key || abs(shownStartMs - startMs) > 3000
    }

    static func isUrl(_ url: String) -> Bool {
        !url.isEmpty && url.utf16.count <= 512 && url.hasPrefix("https://")
    }

    static func json(_ object: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes, .sortedKeys])) ?? Data("null".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
