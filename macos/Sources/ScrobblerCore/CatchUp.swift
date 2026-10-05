import Foundation

/// "Catch up on plays from other devices" (Mac only). The Music library records the end time of
/// the latest play of each library song, including plays on an iPhone or iPad synced through
/// iCloud. Songs this app didn't see playing, and that Last.fm doesn't already have (another
/// scrobbler, like the Last.fm iPhone app, may have sent them), are scrobbled with their real time.
/// Limits: library songs only, only the latest play of each song, and it needs Music access.
public enum CatchUp {
    /// A play from Music's library history.
    public struct Play: Equatable {
        public var artist: String
        public var title: String
        public var album: String
        /// Seconds.
        public var duration: Int
        /// When the play ended (Music's "played date").
        public var playedDate: Date

        public init(artist: String, title: String, album: String, duration: Int, playedDate: Date) {
            self.artist = artist
            self.title = title
            self.album = album
            self.duration = duration
            self.playedDate = playedDate
        }

        /// Music records a play when it ends, so it started one song length earlier.
        public var started: Date { playedDate.addingTimeInterval(-Double(duration)) }
        public var key: String { CatchUp.key(artist, title) }
    }

    /// A song this app saw playing, from `first` to `last` (persisted 14 days).
    public struct Sighting: Codable, Equatable {
        public var key: String
        public var first: Date
        public var last: Date

        public init(key: String, first: Date, last: Date) {
            self.key = key
            self.first = first
            self.last = last
        }
    }

    /// A scrobble already on Last.fm.
    public struct Scrobbled: Equatable {
        public var key: String
        public var time: Date

        public init(artist: String, title: String, time: Date) {
            key = CatchUp.key(artist, title)
            self.time = time
        }
    }

    /// Last.fm doesn't accept scrobbles older than 14 days; stay well inside that.
    public static let maxAge: TimeInterval = 13 * 24 * 3600
    /// Leave very recent plays for a while, in case another device's scrobbler is about to send them.
    public static let minAge: TimeInterval = 10 * 60
    public static let margin: TimeInterval = 5 * 60

    /// Artist and title without case, accents, punctuation or remaster tags, so differently written
    /// copies of the same song match.
    public static func key(_ artist: String, _ title: String) -> String {
        AppleMusicLinks.normalize(MainArtist.firstArtist(artist) ?? artist) + "\n" + AppleMusicLinks.normalize(TitleCleaner.cleanTitle(title))
    }

    /// The plays to scrobble: long enough, between `since` and a few minutes ago, not seen by this app
    /// around that time, not on Last.fm near that time, and not sent already.
    public static func missedPlays(_ plays: [Play], since: Date, now: Date, sightings: [Sighting],
                                   onLastFm: [Scrobbled], alreadySent: [Sighting]) -> [Play] {
        let oldest = max(since, now.addingTimeInterval(-maxAge))
        return plays.filter { play in
            guard PlayTracker.isLongEnough(play.duration), play.duration > 0,
                  play.started >= oldest, play.playedDate <= now.addingTimeInterval(-minAge) else { return false }
            let key = play.key
            let from = play.started.addingTimeInterval(-margin), to = play.playedDate.addingTimeInterval(margin)
            // This app saw it playing (and scrobbled it, or it was paused/ignored/too short on purpose).
            if sightings.contains(where: { $0.key == key && $0.last >= from && $0.first <= to }) { return false }
            // Already on Last.fm, from another scrobbler or an earlier catch-up.
            let window = Double(play.duration) + margin
            if onLastFm.contains(where: { $0.key == key && abs($0.time.timeIntervalSince(play.started)) <= window }) { return false }
            if alreadySent.contains(where: { $0.key == key && abs($0.last.timeIntervalSince(play.playedDate)) < 60 }) { return false }
            return true
        }
        .sorted { $0.playedDate < $1.playedDate }
    }

    /// Records that a song is playing now: extends its latest sighting or starts a new one.
    public static func recording(_ key: String, at now: Date, in sightings: [Sighting]) -> [Sighting] {
        var result = sightings.filter { now.timeIntervalSince($0.last) < 14 * 24 * 3600 }
        if let i = result.lastIndex(where: { $0.key == key }), now.timeIntervalSince(result[i].last) < 120 {
            result[i].last = now
        } else {
            result.append(Sighting(key: key, first: now, last: now))
        }
        return result
    }
}
