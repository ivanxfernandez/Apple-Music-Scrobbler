using Xunit;

namespace AppleMusicScrobbler.Tests
{
    /// <summary>Responses shaped like Last.fm's real ones (October 2026).</summary>
    public class WeekSummaryTests
    {
        const string Recent = @"<?xml version=""1.0"" encoding=""UTF-8""?>
<lfm status=""ok""><recenttracks user=""ivanxfernandez"" page=""1"" perPage=""1"" totalPages=""464"" total=""464"">
<track><artist>Honeyglaze</artist><name>Don&apos;t</name></track></recenttracks></lfm>";

        const string Artists = @"<lfm status=""ok""><topartists user=""ivanxfernandez"" total=""110"">
<artist rank=""1""><name>Twenty One Pilots</name><playcount>56</playcount></artist></topartists></lfm>";

        const string Tracks = @"<lfm status=""ok""><toptracks user=""ivanxfernandez"" total=""310"">
<track rank=""1""><name>Drag Path</name><duration>225</duration><playcount>7</playcount>
<artist><name>twenty one pilots</name><mbid></mbid></artist></track></toptracks></lfm>";

        [Fact]
        public void Reads_the_scrobble_count() => Assert.Equal(464, WeekSummary.ScrobbleCount(Recent));

        [Fact]
        public void Reads_the_top_artist_and_song()
        {
            var artist = WeekSummary.TopArtistFrom(Artists);
            Assert.Equal(("Twenty One Pilots", 56), artist);
            var track = WeekSummary.TopTrackFrom(Tracks);
            Assert.Equal(("twenty one pilots", "Drag Path", 7), track);
        }

        [Fact]
        public void Handles_an_empty_week_and_errors()
        {
            Assert.Null(WeekSummary.TopArtistFrom(@"<lfm status=""ok""><topartists user=""x"" total=""0""></topartists></lfm>"));
            Assert.Null(WeekSummary.ScrobbleCount(@"<lfm status=""failed""><error code=""6"">User not found</error></lfm>"));
            Assert.Null(WeekSummary.TopTrackFrom("not xml"));
        }

        [Fact]
        public void Links_to_the_last_seven_days() =>
            Assert.Equal("https://www.last.fm/user/ivan%20x/library?date_preset=LAST_7_DAYS", WeekSummary.Url("ivan x"));

        [Fact]
        public void Pauses_until_a_time()
        {
            var settings = new Settings();
            Assert.False(settings.IsPaused(1000));
            settings.PausedUntil = 4600;
            Assert.True(settings.IsPaused(1000));
            Assert.False(settings.IsPaused(4601));
            settings.PausedUntil = 0;
            settings.Paused = true;
            Assert.True(settings.IsPaused(1000000));
        }
    }
}
