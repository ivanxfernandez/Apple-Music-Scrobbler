import Testing
@testable import ScrobblerCore

/// Port of tests/AppleMusicScrobbler.Tests/PlayTrackerTests.cs: the scrobble rules must match Windows.
@Suite struct PlayTrackerTests {
    /// Drives a PlayTracker one simulated second at a time, like the real 1-second timer.
    final class Simulation {
        private let tracker = PlayTracker()
        var now: Int64 = 1_700_000_000
        var nowPlayingCount = 0
        var scrobbles: [Int64] = []
        /// Seconds into the simulation at which each scrobble happened.
        var scrobbledAfter: [Int] = []
        private var seconds = 0
        /// The C# test shares one NowPlaying object, so a pause keeps the position the song reached.
        private var lastPosition = 0.0

        func play(_ track: NowPlaying, _ seconds: Int, fromPosition: Double = 0) {
            var track = track
            for i in stride(from: 1, through: seconds, by: 1) {
                track.isPlaying = true
                track.position = fromPosition + Double(i)
                step(track, 1)
            }
        }

        func pause(_ track: NowPlaying, _ seconds: Int) {
            var track = track
            track.position = lastPosition
            for _ in 0..<seconds {
                track.isPlaying = false
                step(track, 1)
            }
        }

        func step(_ track: NowPlaying?, _ elapsed: Double) {
            now += Int64(elapsed)
            seconds += Int(elapsed)
            if let track { lastPosition = track.position }
            let events = tracker.update(track, elapsedSeconds: elapsed, unixNow: now)
            if events.nowPlaying { nowPlayingCount += 1 }
            if let at = events.scrobbleAt {
                scrobbles.append(at)
                scrobbledAfter.append(seconds)
            }
        }
    }

    static func song(_ duration: Int, _ title: String = "Song") -> NowPlaying {
        NowPlaying(artist: "Artist", title: title, album: "Album", duration: duration)
    }

    @Test func scrobblesAfterHalfTheSong() {
        let sim = Simulation()
        sim.play(Self.song(200), 99)
        #expect(sim.scrobbles.isEmpty)
        sim.play(Self.song(200), 1, fromPosition: 99)
        #expect(sim.scrobbles.count == 1)
    }

    @Test func longSongsScrobbleAfterFourMinutes() {
        let sim = Simulation()
        sim.play(Self.song(600), 300)
        #expect(sim.scrobbledAfter == [240])
    }

    @Test func songsOf30SecondsOrLessNeverScrobble() {
        let sim = Simulation()
        sim.play(Self.song(30), 30)
        #expect(sim.scrobbles.isEmpty)
        sim.play(Self.song(31, "Slightly longer"), 31)
        #expect(sim.scrobbles.count == 1)
    }

    @Test func unknownDurationNeedsFourMinutes() {
        let sim = Simulation()
        sim.play(Self.song(0), 239)
        #expect(sim.scrobbles.isEmpty)
        sim.play(Self.song(0), 1, fromPosition: 239)
        #expect(sim.scrobbles.count == 1)
    }

    @Test func eachListenScrobblesOnlyOnce() {
        let sim = Simulation()
        sim.play(Self.song(200), 200)
        #expect(sim.scrobbles.count == 1)
    }

    @Test func pausedTimeDoesNotCount() {
        let sim = Simulation()
        let song = Self.song(200)
        sim.play(song, 50)
        sim.pause(song, 300)
        #expect(sim.scrobbles.isEmpty)
        sim.play(song, 50, fromPosition: 50)
        #expect(sim.scrobbles.count == 1)
    }

    @Test func timestampIsWhenTheSongStartedPlaying() {
        let sim = Simulation()
        let start = sim.now + 1
        sim.play(Self.song(200), 120)
        #expect(sim.scrobbles == [start])
    }

    @Test func skippedSongIsNotScrobbledAndNextSongStartsFresh() {
        let sim = Simulation()
        sim.play(Self.song(200, "Skipped"), 90)
        sim.play(Self.song(200, "Next"), 90)
        #expect(sim.scrobbles.isEmpty)
        sim.play(Self.song(200, "Next"), 10, fromPosition: 90)
        #expect(sim.scrobbles.count == 1)
    }

    @Test func nowPlayingIsSentOnceAfterTwoSeconds() {
        let sim = Simulation()
        let song = Self.song(200)
        sim.play(song, 1)
        #expect(sim.nowPlayingCount == 0)
        sim.play(song, 60, fromPosition: 1)
        #expect(sim.nowPlayingCount == 1)
    }

    @Test func playingASongAgainOnRepeatScrobblesAgain() {
        let sim = Simulation()
        let song = Self.song(200)
        sim.play(song, 200)
        sim.play(song, 200) // position jumps back to the start
        #expect(sim.scrobbles.count == 2)
        #expect(sim.nowPlayingCount == 2)
    }

    @Test func seekingBackEarlyInASongIsNotARepeat() {
        let sim = Simulation()
        let song = Self.song(200)
        sim.play(song, 20)
        sim.play(song, 90, fromPosition: 0) // restarted after only 20s
        #expect(sim.scrobbles.count == 1)
        #expect(sim.scrobbledAfter == [100])
    }

    @Test func longGapsLikeSleepAreNotCountedAsListening() {
        let sim = Simulation()
        let song = Self.song(200)
        sim.play(song, 10)
        sim.step(song, 3600)
        #expect(sim.scrobbles.isEmpty)
    }

    @Test func nothingPlayingOrMissingArtistIsIgnored() {
        let sim = Simulation()
        sim.step(nil, 1)
        sim.play(NowPlaying(title: "Radio station", duration: 0), 300)
        #expect(sim.scrobbles.isEmpty)
        #expect(sim.nowPlayingCount == 0)
    }

    @Test(arguments: [(0, 240.0), (100, 50.0), (480, 240.0), (1000, 240.0)])
    func secondsNeeded(duration: Int, expected: Double) {
        #expect(PlayTracker.secondsNeeded(duration) == expected)
    }
}
