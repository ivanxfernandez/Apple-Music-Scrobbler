using Xunit;

namespace AppleMusicScrobbler.Tests
{
    public class SplitArtistTests
    {
        [Theory]
        // Apple Music for Windows: "Artist — Album" in the artist field, album empty
        [InlineData("Joji — SMITHEREENS", "", "Joji", "SMITHEREENS")]
        [InlineData("Simon & Garfunkel — Bookends", "", "Simon & Garfunkel", "Bookends")]
        // Only the first separator splits; the rest belongs to the album
        [InlineData("Artist — Album — Live", "", "Artist", "Album — Live")]
        // A real album field wins over the one in the artist field
        [InlineData("Artist — Album", "Real Album", "Artist", "Real Album")]
        // Normal data passes through
        [InlineData("Daft Punk", "Discovery", "Daft Punk", "Discovery")]
        [InlineData("Jay-Z", "", "Jay-Z", "")]
        [InlineData("  Spaced  ", "  Out  ", "Spaced", "Out")]
        [InlineData(null, null, "", "")]
        public void Splits_artist_and_album(string artist, string album, string expectedArtist, string expectedAlbum)
        {
            var (a, b) = MediaReader.SplitArtist(artist, album);
            Assert.Equal(expectedArtist, a);
            Assert.Equal(expectedAlbum, b);
        }
    }

    public class TitleCleanerTests
    {
        [Theory]
        [InlineData("Locomotive (Complicity) [2022 Remaster]", "Locomotive (Complicity)")]
        [InlineData("Here Comes the Sun - Remastered 2009", "Here Comes the Sun")]
        [InlineData("Bohemian Rhapsody (Remastered 2011)", "Bohemian Rhapsody")]
        [InlineData("Paint It Black (2009 Digital Remaster)", "Paint It Black")]
        [InlineData("Part 1 - Intro - 2015 Remastered Version", "Part 1 - Intro")]
        // Left alone
        [InlineData("Smells Like Teen Spirit (Live)", "Smells Like Teen Spirit (Live)")]
        [InlineData("Song (feat. Someone)", "Song (feat. Someone)")]
        [InlineData("Song - Acoustic", "Song - Acoustic")]
        [InlineData("Remastered", "Remastered")]
        [InlineData("", "")]
        public void Cleans_titles(string input, string expected) =>
            Assert.Equal(expected, TitleCleaner.CleanTitle(input));

        [Theory]
        [InlineData("Use Your Illusion II (Deluxe Edition)", "Use Your Illusion II")]
        [InlineData("Nevermind (20th Anniversary Super Deluxe)", "Nevermind")]
        [InlineData("Abbey Road (Remastered)", "Abbey Road")]
        [InlineData("Rumours [Expanded Edition]", "Rumours")]
        [InlineData("Album (Bonus Track Version)", "Album")]
        [InlineData("Espresso - Single", "Espresso")]
        [InlineData("Something - EP", "Something")]
        [InlineData("Foo (Deluxe Edition) - EP", "Foo")]
        // Left alone
        [InlineData("SMITHEREENS", "SMITHEREENS")]
        [InlineData("Single", "Single")]
        [InlineData("Live at Wembley", "Live at Wembley")]
        public void Cleans_albums(string input, string expected) =>
            Assert.Equal(expected, TitleCleaner.CleanAlbum(input));

        [Fact]
        public void Apply_keeps_everything_else()
        {
            var np = new NowPlaying { Artist = "Guns N' Roses", Title = "Locomotive [2022 Remaster]", Album = "UYI II (Deluxe Edition)", Duration = 522, Position = 10, IsPlaying = true };
            var cleaned = TitleCleaner.Apply(np);
            Assert.Equal("Guns N' Roses", cleaned.Artist);
            Assert.Equal("Locomotive", cleaned.Title);
            Assert.Equal("UYI II", cleaned.Album);
            Assert.Equal(522, cleaned.Duration);
            Assert.True(cleaned.IsPlaying);
            Assert.Null(TitleCleaner.Apply(null));
        }
    }
}
