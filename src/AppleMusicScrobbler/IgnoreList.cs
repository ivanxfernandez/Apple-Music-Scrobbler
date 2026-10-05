using System;
using System.Collections.Generic;
using System.Linq;
using AppleMusicScrobbler.Discord;

namespace AppleMusicScrobbler
{
    /// <summary>
    /// Artists the user doesn't want scrobbled (or shown on Discord). Matching ignores case, accents
    /// and punctuation, and a collaboration counts as its first artist too: ignoring "Joji" also
    /// covers "Joji &amp; BENEE". Same rules as macos/Sources/ScrobblerCore/IgnoreList.swift.
    /// </summary>
    public static class IgnoreList
    {
        public static bool IsIgnored(string artist, IEnumerable<string> list)
        {
            if (string.IsNullOrEmpty(artist) || list == null) return false;
            var ignored = new HashSet<string>(list.Select(AppleMusicLinks.Normalize).Where(n => n.Length > 0));
            if (ignored.Count == 0) return false;
            if (ignored.Contains(AppleMusicLinks.Normalize(artist))) return true;
            string first = MainArtist.FirstArtist(artist);
            return first != null && ignored.Contains(AppleMusicLinks.Normalize(first));
        }

        /// <summary>The list with the artist added (unless it's already there), sorted for the menu.</summary>
        public static List<string> Adding(string artist, IEnumerable<string> list)
        {
            var result = (list ?? Enumerable.Empty<string>()).ToList();
            string name = (artist ?? "").Trim();
            if (name.Length == 0 || result.Any(a => AppleMusicLinks.Normalize(a) == AppleMusicLinks.Normalize(name))) return result;
            result.Add(name);
            result.Sort(StringComparer.CurrentCultureIgnoreCase);
            return result;
        }

        public static List<string> Removing(string artist, IEnumerable<string> list) =>
            (list ?? Enumerable.Empty<string>()).Where(a => AppleMusicLinks.Normalize(a) != AppleMusicLinks.Normalize(artist)).ToList();
    }
}
