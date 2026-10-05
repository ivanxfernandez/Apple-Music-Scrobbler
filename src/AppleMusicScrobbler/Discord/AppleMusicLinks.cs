using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;
using System.Threading.Tasks;

namespace AppleMusicScrobbler.Discord
{
    public class TrackLinks
    {
        public string ArtworkUrl { get; set; }
        public string TrackUrl { get; set; }
        public string AlbumUrl { get; set; }
        public string ArtistUrl { get; set; }
    }

    /// <summary>
    /// Finds album art and Apple Music links for a track with Apple's public iTunes Search API
    /// (the Windows media controls don't expose artwork as a URL Discord can show). Results are cached.
    /// </summary>
    public class AppleMusicLinks
    {
        [DataContract]
        public class SearchResult
        {
            [DataMember(Name = "artistName")] public string ArtistName { get; set; }
            [DataMember(Name = "trackName")] public string TrackName { get; set; }
            [DataMember(Name = "collectionName")] public string CollectionName { get; set; }
            [DataMember(Name = "artworkUrl100")] public string ArtworkUrl100 { get; set; }
            [DataMember(Name = "trackViewUrl")] public string TrackViewUrl { get; set; }
            [DataMember(Name = "collectionViewUrl")] public string CollectionViewUrl { get; set; }
            [DataMember(Name = "artistViewUrl")] public string ArtistViewUrl { get; set; }
        }

        [DataContract]
        class SearchResponse
        {
            [DataMember(Name = "results")] public List<SearchResult> Results { get; set; }
        }

        const int MaxCacheEntries = 500;
        readonly Dictionary<string, TrackLinks> _cache = new Dictionary<string, TrackLinks>();
        readonly Dictionary<string, Task<TrackLinks>> _pending = new Dictionary<string, Task<TrackLinks>>();

        /// <summary>
        /// Returns true with the links (null if nothing was found) once the lookup has finished;
        /// false while it's still running. Starts the lookup on first call. Call from one thread.
        /// </summary>
        public bool TryGet(string artist, string title, string album, out TrackLinks links)
        {
            string key = artist + "\n" + title + "\n" + album;
            if (_cache.TryGetValue(key, out links)) return true;

            if (!_pending.TryGetValue(key, out var task))
            {
                task = LookupAsync(artist, title, album);
                _pending[key] = task;
            }
            if (!task.IsCompleted) return false;

            _pending.Remove(key);
            links = task.Status == TaskStatus.RanToCompletion ? task.Result : null;
            if (task.IsFaulted) Log.Write("Album art lookup failed: " + task.Exception?.GetBaseException().Message);
            if (_cache.Count >= MaxCacheEntries) _cache.Clear();
            _cache[key] = links;
            return true;
        }

        static async Task<TrackLinks> LookupAsync(string artist, string title, string album)
        {
            var songs = await SearchAsync("song", artist + " " + title).ConfigureAwait(false);
            var song = BestMatch(songs, artist, title, album);
            // Song not found but its album is: the art and album/artist links are still right.
            var source = song ?? AlbumMatch(songs, artist, album);
            if (source == null && album.Length > 0)
                source = AlbumMatch(await SearchAsync("album", artist + " " + album).ConfigureAwait(false), artist, album);
            if (source == null) return null;

            return new TrackLinks
            {
                // artworkUrl100 ends in ".../100x100bb.jpg"; the same path serves bigger sizes.
                ArtworkUrl = source.ArtworkUrl100?.Replace("100x100bb", "512x512bb"),
                TrackUrl = song?.TrackViewUrl,
                AlbumUrl = source.CollectionViewUrl,
                ArtistUrl = source.ArtistViewUrl,
            };
        }

        static async Task<List<SearchResult>> SearchAsync(string entity, string term)
        {
            string url = $"https://itunes.apple.com/search?media=music&entity={entity}&limit=15" +
                         "&country=" + Country() + "&term=" + Uri.EscapeDataString(term);
            using (var response = await Http.Client.GetAsync(url).ConfigureAwait(false))
            {
                if (!response.IsSuccessStatusCode) return new List<SearchResult>();
                byte[] body = await response.Content.ReadAsByteArrayAsync().ConfigureAwait(false);
                var parsed = (SearchResponse)new DataContractJsonSerializer(typeof(SearchResponse)).ReadObject(new MemoryStream(body));
                return parsed.Results ?? new List<SearchResult>();
            }
        }

        /// <summary>A result from the same artist and album (any song), or null.</summary>
        public static SearchResult AlbumMatch(IEnumerable<SearchResult> results, string artist, string album)
        {
            string a = Normalize(artist), al = Normalize(album);
            if (al.Length == 0) return null;
            return (results ?? Enumerable.Empty<SearchResult>()).FirstOrDefault(r =>
                Similar(Normalize(r.ArtistName), a) && Normalize(r.CollectionName) == al);
        }

        static string Country()
        {
            try
            {
                string code = RegionInfo.CurrentRegion.TwoLetterISORegionName;
                if (code.Length == 2 && code.All(char.IsLetter)) return code.ToLowerInvariant();
            }
            catch { }
            return "us";
        }

        /// <summary>The same song (artist and title must match), preferring the right album; or null.</summary>
        public static SearchResult BestMatch(IEnumerable<SearchResult> results, string artist, string title, string album)
        {
            string a = Normalize(artist), t = Normalize(title), al = Normalize(album);
            SearchResult best = null;
            int bestScore = 0;
            foreach (var r in results ?? Enumerable.Empty<SearchResult>())
            {
                if (!Similar(Normalize(r.ArtistName), a)) continue; // wrong artist: never use
                string rt = Normalize(r.TrackName), ral = Normalize(r.CollectionName);
                int score;
                if (rt == t) score = 4;
                else if (Similar(rt, t)) score = 2;
                else continue; // different song
                if (al.Length > 0 && ral == al) score += 3; else if (al.Length > 0 && Similar(ral, al)) score += 1;
                if (score > bestScore) { best = r; bestScore = score; }
            }
            return best;
        }

        static bool Similar(string x, string y) => x.Length > 0 && y.Length > 0 && (x.Contains(y) || y.Contains(x));

        /// <summary>Lowercase letters and digits only (accents removed), so punctuation/casing differences don't matter.</summary>
        internal static string Normalize(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            var sb = new StringBuilder();
            foreach (char c in s.Normalize(NormalizationForm.FormD))
            {
                if (CharUnicodeInfo.GetUnicodeCategory(c) == UnicodeCategory.NonSpacingMark) continue;
                if (char.IsLetterOrDigit(c)) sb.Append(char.ToLowerInvariant(c));
            }
            return sb.ToString();
        }
    }
}
