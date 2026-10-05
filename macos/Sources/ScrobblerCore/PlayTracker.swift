import Foundation

public struct PlayEvents {
    /// The track has been playing long enough to announce it as "now playing".
    public var nowPlaying = false
    /// Set when the current listen just started counting as a scrobble: the Unix time it started.
    public var scrobbleAt: Int64?
}

/// Decides, from once-a-second snapshots of the player, when to announce "now playing" and when a
/// listen counts as a scrobble. Last.fm rules: the track is longer than 30 seconds and has been
/// played for half its length or 4 minutes, whichever comes first. Paused time doesn't count.
/// No I/O or clock access, so it's fully unit-testable. Same rules as the Windows PlayTracker.cs.
public final class PlayTracker {
    public static let nowPlayingDelaySeconds = 2.0
    public static let maxSecondsNeeded = 240.0
    public static let minDurationSeconds = 30
    /// Gaps longer than this between updates (Mac asleep, clock changed) aren't counted as listening.
    public static let maxElapsedSeconds = 5.0

    private struct Play {
        var key: String
        var secondsPlayed = 0.0
        var startedAt: Int64 = 0
        var lastPosition: Double
        var nowPlayingSent = false
        var scrobbled = false
    }

    private var play: Play?

    public init() {}

    public static func isLongEnough(_ durationSeconds: Int) -> Bool {
        durationSeconds == 0 || durationSeconds > minDurationSeconds
    }

    /// Seconds of listening needed to scrobble; unknown duration (0) needs 4 minutes.
    public static func secondsNeeded(_ durationSeconds: Int) -> Double {
        durationSeconds > 0 ? min(Double(durationSeconds) / 2, maxSecondsNeeded) : maxSecondsNeeded
    }

    /// - Parameters:
    ///   - np: Current player state, or nil if Music isn't running.
    ///   - elapsedSeconds: Time since the previous update.
    ///   - unixNow: Current Unix time, used as the start time of a new listen.
    public func update(_ np: NowPlaying?, elapsedSeconds: Double, unixNow: Int64) -> PlayEvents {
        var events = PlayEvents()
        guard let np, np.isValid else { return events }
        let elapsed = (elapsedSeconds < 0 || elapsedSeconds > Self.maxElapsedSeconds) ? 0 : elapsedSeconds

        let key = np.artist + "\n" + np.title + "\n" + np.album
        if play == nil || play!.key != key {
            play = Play(key: key, lastPosition: np.position)
        } else if play!.secondsPlayed > 30 && play!.lastPosition > 30 && np.position < 10 {
            play = Play(key: key, lastPosition: np.position) // same song started over (repeat)
        }
        play!.lastPosition = np.position

        guard np.isPlaying else { return events }

        if play!.startedAt == 0 { play!.startedAt = unixNow }
        play!.secondsPlayed += elapsed

        // The short delay avoids reporting a half-updated title/artist during a track change.
        if !play!.nowPlayingSent && play!.secondsPlayed >= Self.nowPlayingDelaySeconds {
            play!.nowPlayingSent = true
            events.nowPlaying = true
        }

        if !play!.scrobbled && Self.isLongEnough(np.duration) && play!.secondsPlayed >= Self.secondsNeeded(np.duration) {
            play!.scrobbled = true
            events.scrobbleAt = play!.startedAt
        }
        return events
    }
}
