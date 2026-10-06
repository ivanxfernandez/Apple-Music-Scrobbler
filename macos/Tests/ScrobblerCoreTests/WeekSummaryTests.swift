import Foundation
import Testing
@testable import ScrobblerCore

/// Responses shaped like Last.fm's real ones (October 2026).
@Suite struct WeekSummaryTests {
    static let recent = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <lfm status="ok">
          <recenttracks user="ivanxfernandez" page="1" perPage="1" totalPages="464" total="464">
            <track><artist>Honeyglaze</artist><name>Don&apos;t</name></track>
          </recenttracks>
        </lfm>
        """.utf8)

    static let artists = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <lfm status="ok">
          <topartists user="ivanxfernandez" page="1" perPage="1" totalPages="110" total="110">
            <artist rank="1"><name>Twenty One Pilots</name><playcount>56</playcount></artist>
          </topartists>
        </lfm>
        """.utf8)

    static let tracks = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <lfm status="ok">
          <toptracks user="ivanxfernandez" page="1" perPage="1" totalPages="310" total="310">
            <track rank="1"><name>Drag Path</name><duration>225</duration><playcount>7</playcount>
              <artist><name>twenty one pilots</name><mbid></mbid></artist></track>
          </toptracks>
        </lfm>
        """.utf8)

    @Test func readsTheScrobbleCount() {
        #expect(WeekSummary.scrobbleCount(fromRecentTracks: Self.recent) == 464)
    }

    @Test func readsTheTopArtistAndSong() throws {
        let artist = try #require(WeekSummary.topArtist(from: Self.artists))
        #expect(artist.name == "Twenty One Pilots" && artist.plays == 56)
        let track = try #require(WeekSummary.topTrack(from: Self.tracks))
        #expect(track.artist == "twenty one pilots" && track.title == "Drag Path" && track.plays == 7)
    }

    @Test func handlesAnEmptyWeekAndErrors() {
        let empty = Data(#"<lfm status="ok"><topartists user="x" total="0"></topartists></lfm>"#.utf8)
        #expect(WeekSummary.topArtist(from: empty) == nil)
        let error = Data(#"<lfm status="failed"><error code="6">User not found</error></lfm>"#.utf8)
        #expect(WeekSummary.scrobbleCount(fromRecentTracks: error) == nil)
        #expect(WeekSummary.topTrack(from: Data("not xml".utf8)) == nil)
    }

    @Test func linksToTheLastSevenDays() {
        #expect(WeekSummary.url(user: "ivan x")?.absoluteString == "https://www.last.fm/user/ivan%20x/library?date_preset=LAST_7_DAYS")
    }
}

@Suite struct PauseTests {
    @Test func pausesUntilATime() throws {
        let defaults = try #require(UserDefaults(suiteName: "PauseTests-\(UUID().uuidString)"))
        let settings = Settings(defaults: defaults, folder: FileManager.default.temporaryDirectory)
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(!settings.isPaused(at: now))
        settings.pausedUntil = now.addingTimeInterval(3600)
        #expect(settings.isPaused(at: now))
        #expect(!settings.isPaused(at: now.addingTimeInterval(3601)))
        settings.pausedUntil = nil
        settings.paused = true
        #expect(settings.isPaused(at: now.addingTimeInterval(1_000_000)))
    }
}
