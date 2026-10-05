import Foundation

/// A scrobble Last.fm accepted, for the "Recent Scrobbles" menu.
public struct RecentScrobble: Codable, Equatable {
    /// Unix time the song started playing.
    public var timestamp: Int64
    public var artist: String
    public var track: String

    public init(timestamp: Int64, artist: String, track: String) {
        self.timestamp = timestamp
        self.artist = artist
        self.track = track
    }

    /// The song's page on Last.fm.
    public var url: URL? {
        URL(string: "https://www.last.fm/music/\(Http.escape(artist))/_/\(Http.escape(track))")
    }
}

public enum RecentScrobbles {
    public static let max = 10

    /// Newest first, at most `max`.
    public static func adding(_ item: RecentScrobble, to list: [RecentScrobble]) -> [RecentScrobble] {
        Array(([item] + list).prefix(max))
    }

    /// "21:40" for today, otherwise "Oct 3, 21:40" (in the user's locale and time zone).
    public static func time(_ item: RecentScrobble, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(item.timestamp))
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(calendar.isDate(date, inSameDayAs: now) ? "jj:mm" : "MMMd jj:mm")
        return formatter.string(from: date)
    }
}
