using Xunit;

namespace AppleMusicScrobbler.Tests
{
    public class MainArtistTests
    {
        [Theory]
        [InlineData("Joji & BENEE", "Joji")]
        [InlineData("twenty one pilots, Arcane & League of Legends Music", "twenty one pilots")]
        [InlineData("Earth, Wind & Fire", "Earth")]
        [InlineData("$uicideboy$ & Germ", "$uicideboy$")]
        [InlineData("Joji", null)]
        [InlineData("AC/DC", null)]
        [InlineData("Florence + the Machine", null)]
        [InlineData(" & Someone", null)]
        [InlineData("", null)]
        public void Finds_the_first_artist(string credit, string expected) =>
            Assert.Equal(expected, MainArtist.FirstArtist(credit));

        [Theory]
        [InlineData("", LoveShortcut.WinAltL)]
        [InlineData("AltShiftL", LoveShortcut.AltShiftL)]
        [InlineData("Off", LoveShortcut.Off)]
        [InlineData("Something else", LoveShortcut.WinAltL)]
        [InlineData("42", LoveShortcut.WinAltL)]
        public void Reads_the_love_shortcut_setting(string value, LoveShortcut expected) =>
            Assert.Equal(expected, LoveShortcuts.Parse(value));

        // Real Last.fm listener counts (October 2026): full credit, first artist alone.
        [Theory]
        [InlineData("Joji & BENEE", 14247, 3177868, true)]
        [InlineData("Anyma & Joji", 1418, 554429, true)]
        [InlineData("Post Malone & Swae Lee", 68630, 3713875, true)]
        [InlineData("Héctor Lavoe & Willie Colón", 1763, 259791, true)]
        [InlineData("twenty one pilots, Arcane & League of Legends Music", 3598, 3567492, true)]
        [InlineData("Los Flakos & te vi en un planetario", 79, 16000, true)]
        [InlineData("Simon & Garfunkel", 3552026, 62545, false)]
        [InlineData("Earth, Wind & Fire", 3090285, 336393, false)]
        [InlineData("Tyler, The Creator", 4517543, 22586, false)]
        [InlineData("Hall & Oates", 836974, 14880, false)]
        [InlineData("Mumford & Sons", 2747016, 2195, false)]
        [InlineData("Crosby, Stills, Nash & Young", 1409839, 5944, false)]
        [InlineData("Unknown & Nobody", 0, 0, false)]
        public void Decides_with_Last_fm_listeners(string credit, long full, long first, bool collaboration)
        {
            Assert.NotNull(credit);
            Assert.Equal(collaboration, MainArtist.IsCollaboration(full, first));
        }
    }
}
