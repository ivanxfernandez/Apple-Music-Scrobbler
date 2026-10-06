using System;
using System.Collections.Generic;
using System.Text;
using System.Threading.Tasks;
using System.Xml.Linq;

namespace AppleMusicScrobbler
{
    /// <summary>
    /// "Your week": the last 7 days on Last.fm (scrobble count, top artist and top song).
    /// Same as macos/Sources/ScrobblerCore/WeekSummary.swift.
    /// </summary>
    public class WeekSummary
    {
        public int Scrobbles { get; set; }
        public string TopArtist { get; set; }
        public int TopArtistPlays { get; set; }
        public string TopTrackArtist { get; set; }
        public string TopTrack { get; set; }
        public int TopTrackPlays { get; set; }

        /// <summary>The user's library page filtered to the last 7 days.</summary>
        public static string Url(string user) =>
            "https://www.last.fm/user/" + Uri.EscapeDataString(user ?? "") + "/library?date_preset=LAST_7_DAYS";

        // Parsing the three Last.fm responses, kept separate so they can be tested.

        /// <summary>user.getRecentTracks: the "total" attribute counts scrobbles in the requested time range.</summary>
        public static int? ScrobbleCount(string xml)
        {
            var root = Ok(xml);
            return int.TryParse((string)root?.Element("recenttracks")?.Attribute("total"), out int total) ? total : (int?)null;
        }

        public static (string Name, int Plays)? TopArtistFrom(string xml)
        {
            var artist = Ok(xml)?.Element("topartists")?.Element("artist");
            string name = ((string)artist?.Element("name"))?.Trim();
            if (string.IsNullOrEmpty(name)) return null;
            int.TryParse((string)artist.Element("playcount"), out int plays);
            return (name, plays);
        }

        public static (string Artist, string Title, int Plays)? TopTrackFrom(string xml)
        {
            var track = Ok(xml)?.Element("toptracks")?.Element("track");
            string title = ((string)track?.Element("name"))?.Trim();
            if (string.IsNullOrEmpty(title)) return null;
            int.TryParse((string)track.Element("playcount"), out int plays);
            return (((string)track.Element("artist")?.Element("name"))?.Trim() ?? "", title, plays);
        }

        static XElement Ok(string xml)
        {
            try
            {
                var root = XElement.Parse((xml ?? "").TrimStart('\uFEFF'));
                return (string)root.Attribute("status") == "ok" ? root : null;
            }
            catch
            {
                return null;
            }
        }
    }

    public partial class LastFmClient
    {
        /// <summary>The last 7 days: three small Last.fm requests (no login needed, just the username).</summary>
        public async Task<WeekSummary> GetWeekSummaryAsync(string user)
        {
            long from = DateTimeOffset.UtcNow.AddDays(-7).ToUnixTimeSeconds();
            var recent = GetAsync("user.getRecentTracks", new Dictionary<string, string> { ["user"] = user, ["from"] = from.ToString(), ["limit"] = "1" });
            var artists = GetAsync("user.getTopArtists", new Dictionary<string, string> { ["user"] = user, ["period"] = "7day", ["limit"] = "1" });
            var tracks = GetAsync("user.getTopTracks", new Dictionary<string, string> { ["user"] = user, ["period"] = "7day", ["limit"] = "1" });
            await Task.WhenAll(recent, artists, tracks).ConfigureAwait(false);

            int? count = WeekSummary.ScrobbleCount(recent.Result);
            if (count == null) throw new LastFmException(0, "Couldn't read your Last.fm stats");
            var top = WeekSummary.TopArtistFrom(artists.Result);
            var song = WeekSummary.TopTrackFrom(tracks.Result);
            return new WeekSummary
            {
                Scrobbles = count.Value,
                TopArtist = top?.Name,
                TopArtistPlays = top?.Plays ?? 0,
                TopTrackArtist = song?.Artist,
                TopTrack = song?.Title,
                TopTrackPlays = song?.Plays ?? 0,
            };
        }

        /// <summary>An unauthenticated read (GET with the API key), returning the raw XML.</summary>
        async Task<string> GetAsync(string method, IDictionary<string, string> args)
        {
            var url = new StringBuilder(ApiUrl + "?method=" + Uri.EscapeDataString(method) + "&api_key=" + Uri.EscapeDataString(_settings.EffectiveApiKey));
            foreach (var kv in args) url.Append('&').Append(Uri.EscapeDataString(kv.Key)).Append('=').Append(Uri.EscapeDataString(kv.Value));
            using (var response = await Http.Client.GetAsync(url.ToString()).ConfigureAwait(false))
                return Encoding.UTF8.GetString(await response.Content.ReadAsByteArrayAsync().ConfigureAwait(false));
        }
    }
}
