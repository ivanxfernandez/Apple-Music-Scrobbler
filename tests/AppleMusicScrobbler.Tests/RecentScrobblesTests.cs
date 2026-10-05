using System;
using System.Collections.Generic;
using System.Globalization;
using Xunit;

namespace AppleMusicScrobbler.Tests
{
    public class RecentScrobblesTests
    {
        static RecentScrobble Item(int i) => new RecentScrobble { Timestamp = i, Artist = "A", Track = "T" + i };

        [Fact]
        public void Keeps_the_newest_ten_newest_first()
        {
            var list = new List<RecentScrobble>();
            for (int i = 1; i <= 12; i++) list = RecentScrobbles.Adding(Item(i), list);
            Assert.Equal(10, list.Count);
            Assert.Equal("T12", list[0].Track);
            Assert.Equal("T3", list[9].Track);
        }

        [Fact]
        public void Shows_the_time_today_and_the_date_before()
        {
            var culture = CultureInfo.GetCultureInfo("en-US");
            var now = new DateTime(2026, 10, 4, 23, 20, 0, DateTimeKind.Local);
            var today = new RecentScrobble { Timestamp = new DateTimeOffset(new DateTime(2026, 10, 4, 22, 5, 0, DateTimeKind.Local)).ToUnixTimeSeconds() };
            var earlier = new RecentScrobble { Timestamp = new DateTimeOffset(new DateTime(2026, 10, 2, 9, 30, 0, DateTimeKind.Local)).ToUnixTimeSeconds() };
            Assert.Equal("10:05 PM", RecentScrobbles.Time(today, now, culture));
            Assert.Equal("Oct 2, 9:30 AM", RecentScrobbles.Time(earlier, now, culture));
        }

        [Fact]
        public void Links_to_the_song_on_Last_fm() =>
            Assert.Equal("https://www.last.fm/music/AC%2FDC/_/T.N.T.", new RecentScrobble { Artist = "AC/DC", Track = "T.N.T." }.Url);
    }
}
