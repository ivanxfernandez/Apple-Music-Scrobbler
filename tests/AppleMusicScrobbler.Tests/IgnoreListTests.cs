using Xunit;

namespace AppleMusicScrobbler.Tests
{
    public class IgnoreListTests
    {
        [Fact]
        public void Matches_ignoring_case_accents_and_punctuation()
        {
            var list = new[] { "José José", "AC/DC" };
            Assert.True(IgnoreList.IsIgnored("jose jose", list));
            Assert.True(IgnoreList.IsIgnored("AC-DC", list));
            Assert.False(IgnoreList.IsIgnored("Joji", list));
            Assert.False(IgnoreList.IsIgnored("Joji", new string[0]));
            Assert.False(IgnoreList.IsIgnored("Joji", null));
        }

        [Fact]
        public void Covers_collaborations_of_an_ignored_artist()
        {
            Assert.True(IgnoreList.IsIgnored("Joji & BENEE", new[] { "Joji" }));
            Assert.True(IgnoreList.IsIgnored("Joji & BENEE", new[] { "joji & benee" }));
            // Only the first artist counts, so ignoring a guest doesn't hide the main artist's songs.
            Assert.False(IgnoreList.IsIgnored("Joji & BENEE", new[] { "BENEE" }));
        }

        [Fact]
        public void Adds_once_and_keeps_the_list_sorted()
        {
            var list = IgnoreList.Adding("Zoé", null);
            list = IgnoreList.Adding("bôa", list);
            list = IgnoreList.Adding("ZOE", list);
            list = IgnoreList.Adding("  ", list);
            Assert.Equal(new[] { "bôa", "Zoé" }, list);
            Assert.Equal(new[] { "bôa" }, IgnoreList.Removing("zoe", list));
        }
    }
}
