using System.Text.RegularExpressions;

namespace AppleMusicScrobbler
{
    /// <summary>
    /// Strips release-version noise that Apple Music adds to names, so scrobbles land on the same
    /// Last.fm track/album pages as everyone else's (instead of splitting your play counts):
    ///   "Locomotive (Complicity) [2022 Remaster]"  -> "Locomotive (Complicity)"
    ///   "Here Comes the Sun - Remastered 2009"     -> "Here Comes the Sun"
    ///   "Use Your Illusion II (Deluxe Edition)"    -> "Use Your Illusion II"   (album)
    ///   "Espresso - Single"                         -> "Espresso"               (album)
    /// "feat." credits, live/acoustic versions, remixes etc. are left alone.
    /// </summary>
    public static class TitleCleaner
    {
        const RegexOptions Options = RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled;

        // "(2011 Remaster)", "[Remastered 2009]", "(2009 Digital Remaster)", "(Remastered Version)"
        static readonly Regex BracketedRemaster = new Regex(@"\s*[\(\[][^\(\)\[\]]*\bremaster(ed)?\b[^\(\)\[\]]*[\)\]]", Options);

        // " - 2011 Remaster", " - Remastered 2009", " - 2015 Remastered Version" (last dash-separated part only)
        static readonly Regex DashedRemaster = new Regex(@"\s+[-–—]\s+[^-–—]*\bremaster(ed)?\b[^-–—]*$", Options);

        // Albums: "(Deluxe Edition)", "[Expanded Version]", "(20th Anniversary Edition)", "(Bonus Track Version)"
        static readonly Regex AlbumEdition = new Regex(
            @"\s*[\(\[][^\(\)\[\]]*\b(deluxe|expanded|bonus tracks?|anniversary|special edition|collector'?s edition|legacy edition)\b[^\(\)\[\]]*[\)\]]", Options);

        // Albums: " - Single", " - EP"
        static readonly Regex SingleOrEp = new Regex(@"\s+-\s+(single|ep)$", Options);

        public static string CleanTitle(string title) => Clean(title, BracketedRemaster, DashedRemaster);

        public static string CleanAlbum(string album) => Clean(album, BracketedRemaster, DashedRemaster, AlbumEdition, SingleOrEp);

        public static NowPlaying Apply(NowPlaying np) => np == null ? null : new NowPlaying
        {
            Artist = np.Artist,
            Title = CleanTitle(np.Title),
            Album = CleanAlbum(np.Album),
            Duration = np.Duration,
            Position = np.Position,
            IsPlaying = np.IsPlaying,
        };

        static string Clean(string text, params Regex[] patterns)
        {
            if (string.IsNullOrEmpty(text)) return text ?? "";
            string result = text;
            foreach (var pattern in patterns) result = pattern.Replace(result, "");
            result = result.Trim();
            return result.Length > 0 ? result : text; // never clean a name down to nothing
        }
    }
}
