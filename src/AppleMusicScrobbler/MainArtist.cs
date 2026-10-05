using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace AppleMusicScrobbler
{
    /// <summary>
    /// "Scrobble only the main artist": Apple Music credits collaborations as one artist
    /// ("Joji & BENEE"), which Last.fm counts as a separate artist from "Joji". Band names look the
    /// same ("Simon & Garfunkel"), so Last.fm's own listener counts decide: a collaboration's combined
    /// name has a tiny fraction of the first artist's listeners (under 2% in every case checked),
    /// while a band's name has far more listeners than its first word.
    /// Same rules as macos/Sources/ScrobblerCore/MainArtist.swift.
    /// </summary>
    public static class MainArtist
    {
        /// <summary>The full credit must have fewer than this share of the first artist's listeners.</summary>
        public const double MaxShare = 0.10;

        static readonly string[] Separators = { " & ", ", " };

        /// <summary>The first artist of a credit like "A &amp; B" or "A, B &amp; C", or null if there's only one.</summary>
        public static string FirstArtist(string artist)
        {
            if (string.IsNullOrEmpty(artist)) return null;
            int cut = Separators.Select(s => artist.IndexOf(s, StringComparison.Ordinal)).Where(i => i >= 0).DefaultIfEmpty(-1).Min();
            if (cut < 0) return null;
            string first = artist.Substring(0, cut).Trim();
            return first.Length > 0 ? first : null;
        }

        /// <summary>True when the credit is a collaboration that should be scrobbled as its first artist.</summary>
        public static bool IsCollaboration(long fullListeners, long firstListeners) =>
            firstListeners > 0 && fullListeners < firstListeners * MaxShare;
    }

    /// <summary>
    /// Looks up and remembers which credits are collaborations. Call Resolve once a second from the
    /// UI thread; it starts the Last.fm lookups the first time it sees a credit.
    /// </summary>
    public class MainArtistResolver
    {
        readonly LastFmClient _api;
        readonly Dictionary<string, string> _cache = new Dictionary<string, string>();
        readonly Dictionary<string, Task<string>> _pending = new Dictionary<string, Task<string>>();

        public MainArtistResolver(LastFmClient api)
        {
            _api = api;
        }

        /// <summary>
        /// The artist to scrobble for this credit: the main artist once Last.fm confirmed it's a
        /// collaboration, otherwise the credit itself (also while the lookup is running).
        /// </summary>
        public string Resolve(string artist)
        {
            if (_cache.TryGetValue(artist, out var known)) return known;
            string first = MainArtist.FirstArtist(artist);
            if (first == null) return artist;

            if (!_pending.TryGetValue(artist, out var task))
            {
                task = LookupAsync(artist, first);
                _pending[artist] = task;
            }
            if (!task.IsCompleted) return artist;

            _pending.Remove(artist);
            string result = task.Status == TaskStatus.RanToCompletion ? task.Result : artist;
            if (_cache.Count > 500) _cache.Clear();
            _cache[artist] = result;
            return result;
        }

        async Task<string> LookupAsync(string artist, string first)
        {
            try
            {
                var full = _api.GetArtistListenersAsync(artist);
                var main = _api.GetArtistListenersAsync(first);
                await Task.WhenAll(full, main).ConfigureAwait(false);
                if (MainArtist.IsCollaboration(full.Result, main.Result))
                {
                    Log.Write($"Collaboration: scrobbling \"{artist}\" as \"{first}\"");
                    return first;
                }
            }
            catch (Exception ex)
            {
                Log.Write($"Couldn't check whether \"{artist}\" is a collaboration: {ex.Message}");
            }
            return artist;
        }
    }
}
