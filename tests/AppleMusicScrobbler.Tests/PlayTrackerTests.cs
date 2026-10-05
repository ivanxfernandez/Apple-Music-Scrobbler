using System.Collections.Generic;
using Xunit;

namespace AppleMusicScrobbler.Tests
{
    public class PlayTrackerTests
    {
        /// <summary>Drives a PlayTracker one simulated second at a time, like the real 1-second timer.</summary>
        class Simulation
        {
            readonly PlayTracker _tracker = new PlayTracker();
            public long Now = 1_700_000_000;
            public int NowPlayingCount;
            public readonly List<long> Scrobbles = new List<long>();
            /// <summary>Seconds into the simulation at which each scrobble happened.</summary>
            public readonly List<int> ScrobbledAfter = new List<int>();
            int _seconds;

            public void Play(NowPlaying track, int seconds, double fromPosition = 0)
            {
                for (int i = 1; i <= seconds; i++)
                {
                    track.IsPlaying = true;
                    track.Position = fromPosition + i;
                    Step(track, 1);
                }
            }

            public void Pause(NowPlaying track, int seconds)
            {
                for (int i = 0; i < seconds; i++)
                {
                    track.IsPlaying = false;
                    Step(track, 1);
                }
            }

            public void Step(NowPlaying track, double elapsed)
            {
                Now += (long)elapsed;
                _seconds += (int)elapsed;
                var events = _tracker.Update(track, elapsed, Now);
                if (events.NowPlaying) NowPlayingCount++;
                if (events.ScrobbleAt.HasValue)
                {
                    Scrobbles.Add(events.ScrobbleAt.Value);
                    ScrobbledAfter.Add(_seconds);
                }
            }
        }

        static NowPlaying Song(int duration, string title = "Song") =>
            new NowPlaying { Artist = "Artist", Title = title, Album = "Album", Duration = duration };

        [Fact]
        public void Scrobbles_after_half_the_song()
        {
            var sim = new Simulation();
            sim.Play(Song(200), 99);
            Assert.Empty(sim.Scrobbles);
            sim.Play(Song(200), 1, fromPosition: 99);
            Assert.Single(sim.Scrobbles);
        }

        [Fact]
        public void Long_songs_scrobble_after_four_minutes()
        {
            var sim = new Simulation();
            var song = Song(600);
            sim.Play(song, 300);
            Assert.Equal(new[] { 240 }, sim.ScrobbledAfter);
        }

        [Fact]
        public void Songs_of_30_seconds_or_less_never_scrobble()
        {
            var sim = new Simulation();
            sim.Play(Song(30), 30);
            Assert.Empty(sim.Scrobbles);

            sim.Play(Song(31, "Slightly longer"), 31);
            Assert.Single(sim.Scrobbles);
        }

        [Fact]
        public void Unknown_duration_needs_four_minutes()
        {
            var sim = new Simulation();
            sim.Play(Song(0), 239);
            Assert.Empty(sim.Scrobbles);
            sim.Play(Song(0), 1, fromPosition: 239);
            Assert.Single(sim.Scrobbles);
        }

        [Fact]
        public void Each_listen_scrobbles_only_once()
        {
            var sim = new Simulation();
            sim.Play(Song(200), 200);
            Assert.Single(sim.Scrobbles);
        }

        [Fact]
        public void Paused_time_does_not_count()
        {
            var sim = new Simulation();
            var song = Song(200);
            sim.Play(song, 50);
            sim.Pause(song, 300);
            Assert.Empty(sim.Scrobbles);
            sim.Play(song, 50, fromPosition: 50);
            Assert.Single(sim.Scrobbles);
        }

        [Fact]
        public void Timestamp_is_when_the_song_started_playing()
        {
            var sim = new Simulation();
            long start = sim.Now + 1;
            sim.Play(Song(200), 120);
            Assert.Equal(new[] { start }, sim.Scrobbles);
        }

        [Fact]
        public void Skipped_song_is_not_scrobbled_and_next_song_starts_fresh()
        {
            var sim = new Simulation();
            sim.Play(Song(200, "Skipped"), 90);
            sim.Play(Song(200, "Next"), 90);
            Assert.Empty(sim.Scrobbles);
            sim.Play(Song(200, "Next"), 10, fromPosition: 90);
            Assert.Single(sim.Scrobbles);
        }

        [Fact]
        public void Now_playing_is_sent_once_after_two_seconds()
        {
            var sim = new Simulation();
            var song = Song(200);
            sim.Play(song, 1);
            Assert.Equal(0, sim.NowPlayingCount);
            sim.Play(song, 60, fromPosition: 1);
            Assert.Equal(1, sim.NowPlayingCount);
        }

        [Fact]
        public void Playing_a_song_again_on_repeat_scrobbles_again()
        {
            var sim = new Simulation();
            var song = Song(200);
            sim.Play(song, 200);
            sim.Play(song, 200); // position jumps back to the start
            Assert.Equal(2, sim.Scrobbles.Count);
            Assert.Equal(2, sim.NowPlayingCount);
        }

        [Fact]
        public void Seeking_back_early_in_a_song_is_not_a_repeat()
        {
            var sim = new Simulation();
            var song = Song(200);
            sim.Play(song, 20);
            sim.Play(song, 90, fromPosition: 0); // restarted after only 20s
            Assert.Single(sim.Scrobbles);
            Assert.Equal(new[] { 100 }, sim.ScrobbledAfter);
        }

        [Fact]
        public void Long_gaps_like_sleep_are_not_counted_as_listening()
        {
            var sim = new Simulation();
            var song = Song(200);
            sim.Play(song, 10);
            sim.Step(song, 3600);
            Assert.Empty(sim.Scrobbles);
        }

        [Fact]
        public void Nothing_playing_or_missing_artist_is_ignored()
        {
            var sim = new Simulation();
            sim.Step(null, 1);
            sim.Play(new NowPlaying { Title = "Radio station", Duration = 0 }, 300);
            Assert.Empty(sim.Scrobbles);
            Assert.Equal(0, sim.NowPlayingCount);
        }

        [Theory]
        [InlineData(0, 240)]
        [InlineData(100, 50)]
        [InlineData(480, 240)]
        [InlineData(1000, 240)]
        public void Seconds_needed(int duration, double expected) =>
            Assert.Equal(expected, PlayTracker.SecondsNeeded(duration));
    }
}
