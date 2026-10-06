import Foundation

/// "Your week": the last 7 days on Last.fm (scrobble count, top artist and top song).
public struct WeekSummary: Equatable {
    public var scrobbles: Int
    public var topArtist: String?
    public var topArtistPlays: Int
    public var topTrackArtist: String?
    public var topTrack: String?
    public var topTrackPlays: Int

    public init(scrobbles: Int, topArtist: String? = nil, topArtistPlays: Int = 0, topTrackArtist: String? = nil, topTrack: String? = nil, topTrackPlays: Int = 0) {
        self.scrobbles = scrobbles
        self.topArtist = topArtist
        self.topArtistPlays = topArtistPlays
        self.topTrackArtist = topTrackArtist
        self.topTrack = topTrack
        self.topTrackPlays = topTrackPlays
    }

    /// The user's library page filtered to the last 7 days.
    public static func url(user: String) -> URL? {
        URL(string: "https://www.last.fm/user/\(Http.escape(user))/library?date_preset=LAST_7_DAYS")
    }

    // Parsing the three Last.fm responses (XML), kept separate so they can be tested.

    /// user.getRecentTracks: the "total" attribute counts scrobbles in the requested time range.
    public static func scrobbleCount(fromRecentTracks xml: Data) -> Int? {
        guard let root = ok(xml), let total = attribute(root, "recenttracks", "total") else { return nil }
        return Int(total)
    }

    /// user.getTopArtists: the first artist and its play count.
    public static func topArtist(from xml: Data) -> (name: String, plays: Int)? {
        guard let root = ok(xml), let artist = (try? root.nodes(forXPath: "topartists/artist").first) as? XMLElement,
              let name = value(artist, "name"), !name.isEmpty else { return nil }
        return (name, Int(value(artist, "playcount") ?? "") ?? 0)
    }

    /// user.getTopTracks: the first track, its artist and play count.
    public static func topTrack(from xml: Data) -> (artist: String, title: String, plays: Int)? {
        guard let root = ok(xml), let track = (try? root.nodes(forXPath: "toptracks/track").first) as? XMLElement,
              let title = value(track, "name"), !title.isEmpty else { return nil }
        return (value(track, "artist/name") ?? "", title, Int(value(track, "playcount") ?? "") ?? 0)
    }

    private static func ok(_ xml: Data) -> XMLElement? {
        guard let root = (try? XMLDocument(data: xml))?.rootElement(), root.attribute(forName: "status")?.stringValue == "ok" else { return nil }
        return root
    }

    private static func value(_ element: XMLElement, _ path: String) -> String? {
        ((try? element.nodes(forXPath: path).first?.stringValue) ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func attribute(_ element: XMLElement, _ child: String, _ name: String) -> String? {
        element.elements(forName: child).first?.attribute(forName: name)?.stringValue
    }
}

extension LastFmClient {
    /// The last 7 days: three small Last.fm requests (no login needed, just the username).
    public func weekSummary(user: String, now: Date = Date()) async throws -> WeekSummary {
        let from = Int(now.addingTimeInterval(-7 * 24 * 3600).timeIntervalSince1970)
        async let recent = get("user.getRecentTracks", ["user": user, "from": String(from), "limit": "1"])
        async let artists = get("user.getTopArtists", ["user": user, "period": "7day", "limit": "1"])
        async let tracks = get("user.getTopTracks", ["user": user, "period": "7day", "limit": "1"])
        let (r, a, t) = try await (recent, artists, tracks)
        guard let count = WeekSummary.scrobbleCount(fromRecentTracks: r) else {
            throw LastFmError(code: 0, message: "Couldn't read your Last.fm stats")
        }
        let top = WeekSummary.topArtist(from: a), song = WeekSummary.topTrack(from: t)
        return WeekSummary(scrobbles: count, topArtist: top?.name, topArtistPlays: top?.plays ?? 0,
                           topTrackArtist: song?.artist, topTrack: song?.title, topTrackPlays: song?.plays ?? 0)
    }
}
