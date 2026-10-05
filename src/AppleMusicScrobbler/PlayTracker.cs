using System;

namespace AppleMusicScrobbler
{
    public struct PlayEvents
    {
        /// <summary>The track has been playing long enough to announce it as "now playing".</summary>
        public bool NowPlaying;
        /// <summary>Set when the current listen just started counting as a scrobble: the Unix time it started.</summary>
        public long? ScrobbleAt;
    }

    /// <summary>
    /// Decides, from once-a-second snapshots of the player, when to announce "now playing" and when a
    /// listen counts as a scrobble. Last.fm rules: the track is longer than 30 seconds and has been
    /// played for half its length or 4 minutes, whichever comes first. Paused time doesn't count.
    /// No I/O or clock access, so it's fully unit-testable.
    /// </summary>
    public class PlayTracker
    {
        public const double NowPlayingDelaySeconds = 2;
        public const double MaxSecondsNeeded = 240;
        public const int MinDurationSeconds = 30;
        /// <summary>Gaps longer than this between updates (PC asleep, clock changed) aren't counted as listening.</summary>
        public const double MaxElapsedSeconds = 5;

        class Play
        {
            public string Key;
            public double SecondsPlayed;
            public long StartedAt;
            public double LastPosition;
            public bool NowPlayingSent;
            public bool Scrobbled;
        }

        Play _play;

        public static bool IsLongEnough(int durationSeconds) => durationSeconds == 0 || durationSeconds > MinDurationSeconds;

        /// <summary>Seconds of listening needed to scrobble; unknown duration (0) needs 4 minutes.</summary>
        public static double SecondsNeeded(int durationSeconds) =>
            durationSeconds > 0 ? Math.Min(durationSeconds / 2.0, MaxSecondsNeeded) : MaxSecondsNeeded;

        /// <param name="np">Current player state, or null if Apple Music isn't running.</param>
        /// <param name="elapsedSeconds">Time since the previous update.</param>
        /// <param name="unixNow">Current Unix time, used as the start time of a new listen.</param>
        public PlayEvents Update(NowPlaying np, double elapsedSeconds, long unixNow)
        {
            var events = new PlayEvents();
            if (np == null || !np.IsValid) return events;
            if (elapsedSeconds < 0 || elapsedSeconds > MaxElapsedSeconds) elapsedSeconds = 0;

            string key = np.Artist + "\n" + np.Title + "\n" + np.Album;
            if (_play == null || _play.Key != key)
                _play = new Play { Key = key, LastPosition = np.Position };
            else if (_play.SecondsPlayed > 30 && _play.LastPosition > 30 && np.Position < 10)
                _play = new Play { Key = key, LastPosition = np.Position }; // same song started over (repeat)
            _play.LastPosition = np.Position;

            if (!np.IsPlaying) return events;

            if (_play.StartedAt == 0) _play.StartedAt = unixNow;
            _play.SecondsPlayed += elapsedSeconds;

            // The short delay avoids reporting a half-updated title/artist during a track change.
            if (!_play.NowPlayingSent && _play.SecondsPlayed >= NowPlayingDelaySeconds)
            {
                _play.NowPlayingSent = true;
                events.NowPlaying = true;
            }

            if (!_play.Scrobbled && IsLongEnough(np.Duration) && _play.SecondsPlayed >= SecondsNeeded(np.Duration))
            {
                _play.Scrobbled = true;
                events.ScrobbleAt = _play.StartedAt;
            }
            return events;
        }
    }
}
