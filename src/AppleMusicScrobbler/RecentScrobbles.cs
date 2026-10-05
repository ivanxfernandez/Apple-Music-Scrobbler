using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

namespace AppleMusicScrobbler
{
    /// <summary>A scrobble Last.fm accepted, for the "Recent scrobbles" menu.</summary>
    public class RecentScrobble
    {
        /// <summary>Unix time the song started playing.</summary>
        public long Timestamp { get; set; }
        public string Artist { get; set; } = "";
        public string Track { get; set; } = "";

        /// <summary>The song's page on Last.fm.</summary>
        public string Url => "https://www.last.fm/music/" + Uri.EscapeDataString(Artist ?? "") + "/_/" + Uri.EscapeDataString(Track ?? "");
    }

    /// <summary>Same rules as macos/Sources/ScrobblerCore/RecentScrobbles.swift.</summary>
    public static class RecentScrobbles
    {
        public const int Max = 10;

        /// <summary>Newest first, at most Max.</summary>
        public static List<RecentScrobble> Adding(RecentScrobble item, IEnumerable<RecentScrobble> list) =>
            new[] { item }.Concat(list ?? Enumerable.Empty<RecentScrobble>()).Take(Max).ToList();

        /// <summary>"9:40 PM" for today, otherwise "Oct 3, 9:40 PM" (in the user's culture and time zone).</summary>
        public static string Time(RecentScrobble item, DateTime now, CultureInfo culture = null)
        {
            culture = culture ?? CultureInfo.CurrentCulture;
            DateTime local = DateTimeOffset.FromUnixTimeSeconds(item.Timestamp).LocalDateTime;
            string time = local.ToString("t", culture);
            return local.Date == now.Date ? time : local.ToString("MMM d", culture) + ", " + time;
        }
    }
}
