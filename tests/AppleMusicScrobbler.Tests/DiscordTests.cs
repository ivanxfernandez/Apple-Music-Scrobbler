using System.Collections;
using System.Collections.Generic;
using System.Web.Script.Serialization;
using AppleMusicScrobbler.Discord;
using Xunit;

namespace AppleMusicScrobbler.Tests
{
    public class ActivityBuilderTests
    {
        static readonly NowPlaying Track = new NowPlaying
        {
            Artist = "Joji", Title = "YUKON (INTERLUDE)", Album = "SMITHEREENS", Duration = 141, Position = 7, IsPlaying = true,
        };

        static readonly TrackLinks Links = new TrackLinks
        {
            ArtworkUrl = "https://is1-ssl.mzstatic.com/image/thumb/x/512x512bb.jpg",
            TrackUrl = "https://music.apple.com/us/album/yukon/1?i=2",
            AlbumUrl = "https://music.apple.com/us/album/smithereens/1",
            ArtistUrl = "https://music.apple.com/us/artist/joji/3",
        };

        static Dictionary<string, object> Parse(string json) => new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(json);

        [Fact]
        public void Builds_a_listening_activity_with_art_links_and_progress()
        {
            var a = Parse(ActivityBuilder.Build(Track, Links, 1_000_000, "ivan"));

            Assert.Equal(2, a["type"]);
            Assert.Equal("YUKON (INTERLUDE)", a["details"]);
            Assert.Equal("Joji", a["state"]);
            Assert.Equal(Links.TrackUrl, a["details_url"]);
            Assert.Equal(Links.ArtistUrl, a["state_url"]);

            var timestamps = (Dictionary<string, object>)a["timestamps"];
            Assert.Equal(1_000_000, timestamps["start"]);
            Assert.Equal(1_141_000, timestamps["end"]);

            var assets = (Dictionary<string, object>)a["assets"];
            Assert.Equal(Links.ArtworkUrl, assets["large_image"]);
            Assert.Equal("SMITHEREENS", assets["large_text"]);
            Assert.Equal(Links.AlbumUrl, assets["large_url"]);

            var buttons = (ArrayList)a["buttons"];
            Assert.Equal(2, buttons.Count);
            Assert.Equal("Listen on Apple Music", ((Dictionary<string, object>)buttons[0])["label"]);
            Assert.Equal("https://www.last.fm/user/ivan", ((Dictionary<string, object>)buttons[1])["url"]);
        }

        [Fact]
        public void Without_links_uses_the_fallback_image_and_no_apple_music_button()
        {
            var a = Parse(ActivityBuilder.Build(Track, null, 5, ""));
            Assert.Equal(ActivityBuilder.FallbackImage, ((Dictionary<string, object>)a["assets"])["large_image"]);
            Assert.False(a.ContainsKey("buttons"));
            Assert.False(a.ContainsKey("details_url"));
        }

        [Fact]
        public void Unknown_duration_has_no_end_time()
        {
            var live = new NowPlaying { Artist = "A", Title = "Live set", Duration = 0, IsPlaying = true };
            var timestamps = (Dictionary<string, object>)Parse(ActivityBuilder.Build(live, null, 5, null))["timestamps"];
            Assert.False(timestamps.ContainsKey("end"));
        }

        [Fact]
        public void Escapes_quotes_and_special_characters()
        {
            var odd = new NowPlaying { Artist = "Guns N' Roses", Title = "Say \"Hi\" \\ back\n", Album = "Молчат", Duration = 60 };
            var a = Parse(ActivityBuilder.Build(odd, null, 0, null));
            Assert.Equal("Say \"Hi\" \\ back", a["details"]); // trimmed
            Assert.Equal("Молчат", ((Dictionary<string, object>)a["assets"])["large_text"]);
        }

        [Theory]
        [InlineData("X", 2)]
        [InlineData("", 2)]
        [InlineData("Normal", 6)]
        public void Text_is_at_least_two_characters(string input, int length) =>
            Assert.Equal(length, ActivityBuilder.Text(input).Length);

        [Fact]
        public void Text_is_at_most_128_characters() =>
            Assert.Equal(128, ActivityBuilder.Text(new string('a', 300)).Length);

        [Theory]
        [InlineData("a", 10_000, "a", 10_000, false)]
        [InlineData("a", 10_000, "a", 12_500, false)] // timing jitter
        [InlineData("a", 10_000, "a", 20_000, true)]  // seek
        [InlineData("a", 10_000, "b", 10_000, true)]  // new song
        [InlineData(null, 0, "a", 0, true)]           // nothing shown yet
        public void Updates_on_new_song_or_seek(string shownKey, long shownStart, string key, long start, bool expected) =>
            Assert.Equal(expected, ActivityBuilder.NeedsUpdate(shownKey, shownStart, key, start));
    }

    public class AppleMusicLinksTests
    {
        static AppleMusicLinks.SearchResult R(string artist, string track, string album) =>
            new AppleMusicLinks.SearchResult { ArtistName = artist, TrackName = track, CollectionName = album };

        [Fact]
        public void Prefers_exact_title_and_album()
        {
            var results = new[]
            {
                R("Guns N' Roses", "Locomotive (Complicity)", "Use Your Illusion II (Live)"),
                R("Guns N' Roses", "Locomotive (Complicity)", "Use Your Illusion II"),
                R("Guns N' Roses", "Locomotive (Complicity) [Remastered]", "Use Your Illusion II"),
            };
            var best = AppleMusicLinks.BestMatch(results, "Guns N' Roses", "Locomotive (Complicity)", "Use Your Illusion II");
            Assert.Same(results[1], best);
        }

        [Fact]
        public void Never_picks_a_different_artist()
        {
            var results = new[] { R("Some Cover Band", "Bandito", "Trench") };
            Assert.Null(AppleMusicLinks.BestMatch(results, "twenty one pilots", "Bandito", "Trench"));
        }

        [Fact]
        public void Ignores_case_punctuation_and_accents()
        {
            var results = new[] { R("Beyoncé", "CUFF IT", "RENAISSANCE") };
            Assert.NotNull(AppleMusicLinks.BestMatch(results, "beyonce", "Cuff It", "Renaissance"));
        }

        [Fact]
        public void Requires_some_title_match()
        {
            var results = new[] { R("Joji", "Glimpse of Us", "SMITHEREENS") };
            Assert.Null(AppleMusicLinks.BestMatch(results, "Joji", "YUKON (INTERLUDE)", "SMITHEREENS"));
            Assert.Null(AppleMusicLinks.BestMatch(null, "Joji", "x", "y"));
        }

        [Fact]
        public void Album_match_is_used_when_the_song_itself_isnt_found()
        {
            var results = new[] { R("Joji", "Glimpse of Us", "SMITHEREENS"), R("Joji", "Sanctuary", "Nectar") };
            Assert.Same(results[0], AppleMusicLinks.AlbumMatch(results, "Joji", "SMITHEREENS"));
            Assert.Null(AppleMusicLinks.AlbumMatch(results, "Joji", "BALLADS 1"));
            Assert.Null(AppleMusicLinks.AlbumMatch(results, "Joji", ""));
        }
    }
}
