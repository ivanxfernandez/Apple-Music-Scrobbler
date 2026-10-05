import Foundation
import Testing
@testable import ScrobblerCore

@Suite struct CatchUpTests {
    static let now = Date(timeIntervalSince1970: 1_791_200_000)
    static func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
    static func play(_ title: String, endedMinutesAgo: Double, duration: Int = 240, artist: String = "Peel Dream Magazine") -> CatchUp.Play {
        CatchUp.Play(artist: artist, title: title, album: "A", duration: duration, playedDate: ago(endedMinutesAgo))
    }
    static func missed(_ plays: [CatchUp.Play], since: Date = ago(48 * 60), sightings: [CatchUp.Sighting] = [],
                       onLastFm: [CatchUp.Scrobbled] = [], sent: [CatchUp.Sighting] = []) -> [String] {
        CatchUp.missedPlays(plays, since: since, now: now, sightings: sightings, onLastFm: onLastFm, alreadySent: sent).map(\.title)
    }

    @Test func startsOneSongLengthBeforeMusicRecordedIt() {
        #expect(Self.play("A", endedMinutesAgo: 60, duration: 240).started == Self.ago(64))
    }

    @Test func scrobblesPlaysNobodySent() {
        #expect(Self.missed([Self.play("Lie In the Gutter", endedMinutesAgo: 60)]) == ["Lie In the Gutter"])
    }

    @Test func skipsPlaysAlreadyOnLastFm() {
        let p = Self.play("Lie In the Gutter", endedMinutesAgo: 60)
        // The Last.fm iPhone app's timestamp may differ a little; written differently, too.
        let other = CatchUp.Scrobbled(artist: "peel dream magazine", title: "Lie in the Gutter [2022 Remaster]", time: Self.ago(66))
        #expect(Self.missed([p], onLastFm: [other]).isEmpty)
        // A play of the same song on another day doesn't count.
        let yesterday = CatchUp.Scrobbled(artist: "Peel Dream Magazine", title: "Lie In the Gutter", time: Self.ago(24 * 60))
        #expect(Self.missed([p], onLastFm: [yesterday]) == ["Lie In the Gutter"])
    }

    @Test func skipsPlaysThisAppSaw() {
        let p = Self.play("Lie In the Gutter", endedMinutesAgo: 60)
        let seen = CatchUp.Sighting(key: p.key, first: Self.ago(64), last: Self.ago(61))
        #expect(Self.missed([p], sightings: [seen]).isEmpty)
        let seenLongBefore = CatchUp.Sighting(key: p.key, first: Self.ago(300), last: Self.ago(296))
        #expect(Self.missed([p], sightings: [seenLongBefore]) == ["Lie In the Gutter"])
    }

    @Test func skipsPlaysAlreadySentByCatchUp() {
        let p = Self.play("Lie In the Gutter", endedMinutesAgo: 60)
        let sent = CatchUp.Sighting(key: p.key, first: p.playedDate, last: p.playedDate)
        #expect(Self.missed([p], sent: [sent]).isEmpty)
    }

    @Test func respectsTheTimeLimits() {
        let plays = [
            Self.play("Too recent", endedMinutesAgo: 5),
            Self.play("Before turning it on", endedMinutesAgo: 30 * 60),
            Self.play("Too short", endedMinutesAgo: 60, duration: 30),
            Self.play("Unknown length", endedMinutesAgo: 60, duration: 0),
            Self.play("Second", endedMinutesAgo: 20),
            Self.play("First", endedMinutesAgo: 120),
        ]
        #expect(Self.missed(plays, since: Self.ago(24 * 60)) == ["First", "Second"])
        // Never older than Last.fm accepts.
        #expect(Self.missed([Self.play("Old", endedMinutesAgo: 14 * 24 * 60)], since: .distantPast).isEmpty)
    }

    @Test func recordsSightingsAsOnePerListen() {
        let key = CatchUp.key("A", "T")
        var s = CatchUp.recording(key, at: Self.ago(10), in: [])
        s = CatchUp.recording(key, at: Self.ago(9), in: s)
        #expect(s.count == 1 && s[0].first == Self.ago(10) && s[0].last == Self.ago(9))
        s = CatchUp.recording(key, at: Self.ago(1), in: s) // a later listen of the same song
        #expect(s.count == 2)
        let old = CatchUp.Sighting(key: key, first: Self.ago(15 * 24 * 60), last: Self.ago(15 * 24 * 60))
        #expect(CatchUp.recording(key, at: Self.now, in: [old]).count == 1) // pruned after 14 days
    }
}
