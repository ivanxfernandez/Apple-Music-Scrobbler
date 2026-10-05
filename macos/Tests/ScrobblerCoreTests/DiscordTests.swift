import Foundation
import Testing
@testable import ScrobblerCore

/// Port of DiscordTests.cs.
@Suite struct ActivityBuilderTests {
    static let track = NowPlaying(artist: "Joji", title: "YUKON (INTERLUDE)", album: "SMITHEREENS", duration: 141, position: 7, isPlaying: true)

    static let links = TrackLinks(
        artworkUrl: "https://is1-ssl.mzstatic.com/image/thumb/x/512x512bb.jpg",
        trackUrl: "https://music.apple.com/us/album/yukon/1?i=2",
        albumUrl: "https://music.apple.com/us/album/smithereens/1",
        artistUrl: "https://music.apple.com/us/artist/joji/3")

    static func parse(_ json: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    @Test func buildsAListeningActivityWithArtLinksAndProgress() throws {
        let a = try Self.parse(ActivityBuilder.build(Self.track, links: Self.links, startMs: 1_000_000, lastFmUser: "ivan"))

        #expect(a["type"] as? Int == 2)
        #expect(a["details"] as? String == "YUKON (INTERLUDE)")
        #expect(a["state"] as? String == "Joji")
        #expect(a["details_url"] as? String == Self.links.trackUrl)
        #expect(a["state_url"] as? String == Self.links.artistUrl)

        let timestamps = try #require(a["timestamps"] as? [String: Any])
        #expect(timestamps["start"] as? Int == 1_000_000)
        #expect(timestamps["end"] as? Int == 1_141_000)

        let assets = try #require(a["assets"] as? [String: Any])
        #expect(assets["large_image"] as? String == Self.links.artworkUrl)
        #expect(assets["large_text"] as? String == "SMITHEREENS")
        #expect(assets["large_url"] as? String == Self.links.albumUrl)

        let buttons = try #require(a["buttons"] as? [[String: String]])
        #expect(buttons.count == 2)
        #expect(buttons[0]["label"] == "Listen on Apple Music")
        #expect(buttons[1]["url"] == "https://www.last.fm/user/ivan")
    }

    @Test func withoutLinksUsesTheFallbackImageAndNoAppleMusicButton() throws {
        let a = try Self.parse(ActivityBuilder.build(Self.track, links: nil, startMs: 5, lastFmUser: ""))
        #expect((a["assets"] as? [String: Any])?["large_image"] as? String == ActivityBuilder.fallbackImage)
        #expect(a["buttons"] == nil)
        #expect(a["details_url"] == nil)
    }

    @Test func unknownDurationHasNoEndTime() throws {
        let live = NowPlaying(artist: "A", title: "Live set", duration: 0, isPlaying: true)
        let timestamps = try #require(try Self.parse(ActivityBuilder.build(live, links: nil, startMs: 5, lastFmUser: nil))["timestamps"] as? [String: Any])
        #expect(timestamps["end"] == nil)
    }

    @Test func escapesQuotesAndSpecialCharacters() throws {
        let odd = NowPlaying(artist: "Guns N' Roses", title: "Say \"Hi\" \\ back\n", album: "Молчат", duration: 60)
        let a = try Self.parse(ActivityBuilder.build(odd, links: nil, startMs: 0, lastFmUser: nil))
        #expect(a["details"] as? String == "Say \"Hi\" \\ back") // trimmed
        #expect((a["assets"] as? [String: Any])?["large_text"] as? String == "Молчат")
    }

    @Test func lastFmUserIsEscapedInTheProfileLink() throws {
        let a = try Self.parse(ActivityBuilder.build(Self.track, links: nil, startMs: 0, lastFmUser: "a b"))
        #expect((a["buttons"] as? [[String: String]])?.first?["url"] == "https://www.last.fm/user/a%20b")
    }

    @Test(arguments: [("X", 2), ("", 2), ("Normal", 6)])
    func textIsAtLeastTwoCharacters(input: String, length: Int) {
        #expect(ActivityBuilder.text(input).utf16.count == length)
    }

    @Test func textIsAtMost128Characters() {
        #expect(ActivityBuilder.text(String(repeating: "a", count: 300)).utf16.count == 128)
        // Emoji are two UTF-16 units: never cut one in half
        let emoji = ActivityBuilder.text(String(repeating: "🎵", count: 100))
        #expect(emoji.utf16.count <= 128)
        #expect(emoji.hasSuffix("🎵…"))
    }

    @Test(arguments: [
        ("a" as String?, Int64(10_000), "a", Int64(10_000), false),
        ("a", 10_000, "a", 12_500, false), // timing jitter
        ("a", 10_000, "a", 20_000, true),  // seek
        ("a", 10_000, "b", 10_000, true),  // new song
        (nil, 0, "a", 0, true),            // nothing shown yet
    ])
    func updatesOnNewSongOrSeek(shownKey: String?, shownStart: Int64, key: String, start: Int64, expected: Bool) {
        #expect(ActivityBuilder.needsUpdate(shownKey: shownKey, shownStartMs: shownStart, key: key, startMs: start) == expected)
    }
}

@Suite struct AppleMusicLinksTests {
    typealias R = AppleMusicLinks.SearchResult

    @Test func prefersExactTitleAndAlbum() {
        let results = [
            R(artistName: "Guns N' Roses", trackName: "Locomotive (Complicity)", collectionName: "Use Your Illusion II (Live)"),
            R(artistName: "Guns N' Roses", trackName: "Locomotive (Complicity)", collectionName: "Use Your Illusion II"),
            R(artistName: "Guns N' Roses", trackName: "Locomotive (Complicity) [Remastered]", collectionName: "Use Your Illusion II"),
        ]
        let best = AppleMusicLinks.bestMatch(results, artist: "Guns N' Roses", title: "Locomotive (Complicity)", album: "Use Your Illusion II")
        #expect(best == results[1])
    }

    @Test func neverPicksADifferentArtist() {
        let results = [R(artistName: "Some Cover Band", trackName: "Bandito", collectionName: "Trench")]
        #expect(AppleMusicLinks.bestMatch(results, artist: "twenty one pilots", title: "Bandito", album: "Trench") == nil)
    }

    @Test func ignoresCasePunctuationAndAccents() {
        let results = [R(artistName: "Beyoncé", trackName: "CUFF IT", collectionName: "RENAISSANCE")]
        #expect(AppleMusicLinks.bestMatch(results, artist: "beyonce", title: "Cuff It", album: "Renaissance") != nil)
        #expect(AppleMusicLinks.normalize("José José") == "josejose")
        #expect(AppleMusicLinks.normalize("Молчат Дома") == "молчатдома")
    }

    @Test func requiresSomeTitleMatch() {
        let results = [R(artistName: "Joji", trackName: "Glimpse of Us", collectionName: "SMITHEREENS")]
        #expect(AppleMusicLinks.bestMatch(results, artist: "Joji", title: "YUKON (INTERLUDE)", album: "SMITHEREENS") == nil)
        #expect(AppleMusicLinks.bestMatch(nil, artist: "Joji", title: "x", album: "y") == nil)
    }

    @Test func albumMatchIsUsedWhenTheSongItselfIsntFound() {
        let results = [
            R(artistName: "Joji", trackName: "Glimpse of Us", collectionName: "SMITHEREENS"),
            R(artistName: "Joji", trackName: "Sanctuary", collectionName: "Nectar"),
        ]
        #expect(AppleMusicLinks.albumMatch(results, artist: "Joji", album: "SMITHEREENS") == results[0])
        #expect(AppleMusicLinks.albumMatch(results, artist: "Joji", album: "BALLADS 1") == nil)
        #expect(AppleMusicLinks.albumMatch(results, artist: "Joji", album: "") == nil)
    }
}
