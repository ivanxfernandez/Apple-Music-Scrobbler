using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace AppleMusicScrobbler.Discord
{
    /// <summary>Builds the Discord activity JSON. Pure functions, unit-tested.</summary>
    public static class ActivityBuilder
    {
        /// <summary>Art asset key shown when no album art was found (upload the app icon as "logo" in the Discord app).</summary>
        public const string FallbackImage = "logo";

        /// <summary>A playing track as a "Listening to" activity with artwork, progress bar and links.</summary>
        public static string Build(NowPlaying np, TrackLinks links, long startMs, string lastFmUser)
        {
            var fields = new List<string>
            {
                "\"type\":2",                 // Listening
                "\"status_display_type\":1",  // member list shows "Listening to <artist>"
                "\"details\":" + Json.Str(Text(np.Title)),
                "\"state\":" + Json.Str(Text(np.Artist)),
            };
            if (IsUrl(links?.TrackUrl)) fields.Add("\"details_url\":" + Json.Str(links.TrackUrl));
            if (IsUrl(links?.ArtistUrl)) fields.Add("\"state_url\":" + Json.Str(links.ArtistUrl));

            string timestamps = "\"start\":" + startMs;
            if (np.Duration > 0) timestamps += ",\"end\":" + (startMs + np.Duration * 1000L);
            fields.Add("\"timestamps\":{" + timestamps + "}");

            var assets = new List<string>
            {
                "\"large_image\":" + Json.Str(IsUrl(links?.ArtworkUrl) ? links.ArtworkUrl : FallbackImage),
                "\"large_text\":" + Json.Str(Text(np.Album.Length > 0 ? np.Album : np.Title)),
            };
            if (IsUrl(links?.AlbumUrl)) assets.Add("\"large_url\":" + Json.Str(links.AlbumUrl));
            fields.Add("\"assets\":{" + string.Join(",", assets) + "}");

            var buttons = new List<string>();
            if (IsUrl(links?.TrackUrl)) buttons.Add(Button("Listen on Apple Music", links.TrackUrl));
            if (!string.IsNullOrEmpty(lastFmUser)) buttons.Add(Button("Last.fm profile", "https://www.last.fm/user/" + Uri.EscapeDataString(lastFmUser)));
            if (buttons.Count > 0) fields.Add("\"buttons\":[" + string.Join(",", buttons) + "]");

            return "{" + string.Join(",", fields) + "}";
        }

        /// <summary>Discord requires 2-128 characters.</summary>
        public static string Text(string s)
        {
            s = (s ?? "").Trim();
            if (s.Length > 128) s = s.Substring(0, 127) + "…";
            while (s.Length < 2) s += "​"; // zero-width space
            return s;
        }

        /// <summary>A new track, or the playback position jumped (seek, restart) by more than 3 seconds.</summary>
        public static bool NeedsUpdate(string shownKey, long shownStartMs, string key, long startMs) =>
            shownKey != key || Math.Abs(shownStartMs - startMs) > 3000;

        static string Button(string label, string url) => "{\"label\":" + Json.Str(label) + ",\"url\":" + Json.Str(url) + "}";

        static bool IsUrl(string url) => !string.IsNullOrEmpty(url) && url.Length <= 512 && url.StartsWith("https://", StringComparison.Ordinal);
    }

    /// <summary>
    /// Keeps the Discord "Listening to" status in sync with Apple Music. Called once a second from
    /// the UI thread; only talks to Discord when something visible changed.
    /// </summary>
    public sealed class DiscordPresence : IDisposable
    {
        const int ReconnectSeconds = 15;
        const int MinSecondsBetweenUpdates = 2;   // Discord allows 5 updates per 20 seconds
        const int MaxArtworkWaitSeconds = 3;

        readonly Settings _settings;
        readonly AppleMusicLinks _links = new AppleMusicLinks();
        DiscordIpc _ipc;
        bool _connecting;
        bool _connectFailureLogged;
        DateTime _nextConnect = DateTime.MinValue;
        DateTime _lastSend = DateTime.MinValue;

        // What Discord currently shows: null = unknown, "" = nothing.
        string _shownKey;
        long _shownStartMs;
        bool _shownWithLinks;
        string _waitingKey;
        DateTime _waitingSince;

        public DiscordPresence(Settings settings)
        {
            _settings = settings;
        }

        /// <summary>False when the exe was built without a Discord application ID.</summary>
        public static bool Available => AppInfo.DiscordClientId.Length > 0;

        public bool IsConnected => _ipc?.IsConnected == true;

        public void Update(NowPlaying np)
        {
            if (!Available) return;
            if (!_settings.ShowOnDiscord)
            {
                if (_ipc != null) Disconnect(); // Discord clears the status when we disconnect
                return;
            }

            if (!IsConnected)
            {
                if (_ipc != null)
                {
                    Log.Write("Disconnected from Discord");
                    Disconnect();
                }
                if (!_connecting && DateTime.UtcNow >= _nextConnect) _ = ConnectAsync();
                return;
            }

            if ((DateTime.UtcNow - _lastSend).TotalSeconds < MinSecondsBetweenUpdates) return;

            if (np == null || !np.IsValid || !np.IsPlaying)
            {
                if (_shownKey != "") _ = SendAsync(null, "", 0, false);
                return;
            }

            string key = np.Artist + "\n" + np.Title + "\n" + np.Album;
            long startMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() - (long)(np.Position * 1000);
            bool linksReady = _links.TryGet(np.Artist, np.Title, np.Album, out var links);

            bool changed = ActivityBuilder.NeedsUpdate(_shownKey, _shownStartMs, key, startMs);
            bool artArrived = !changed && !_shownWithLinks && linksReady && links != null;
            if (!changed && !artArrived) return;

            if (!linksReady)
            {
                // Give the album art lookup a moment so the status doesn't flash without a picture.
                if (_waitingKey != key)
                {
                    _waitingKey = key;
                    _waitingSince = DateTime.UtcNow;
                }
                if ((DateTime.UtcNow - _waitingSince).TotalSeconds < MaxArtworkWaitSeconds) return;
            }

            if (artArrived) startMs = _shownStartMs; // keep the progress bar steady
            _ = SendAsync(ActivityBuilder.Build(np, links, startMs, _settings.Username), key, startMs, linksReady && links != null);
        }

        async Task SendAsync(string activityJson, string key, long startMs, bool withLinks)
        {
            _lastSend = DateTime.UtcNow;
            _shownKey = key;
            _shownStartMs = startMs;
            _shownWithLinks = withLinks;
            try
            {
                await _ipc.SetActivityAsync(activityJson);
            }
            catch (Exception ex)
            {
                Log.Write("Couldn't update Discord status: " + ex.Message);
                _shownKey = null;
            }
        }

        async Task ConnectAsync()
        {
            _connecting = true;
            var ipc = new DiscordIpc();
            ipc.Error += message => Log.Write("Discord rejected the status update: " + message);
            try
            {
                await ipc.ConnectAsync(AppInfo.DiscordClientId);
                _ipc = ipc;
                _shownKey = null;
                _lastSend = DateTime.MinValue;
                _connectFailureLogged = false;
                Log.Write("Connected to Discord");
            }
            catch (Exception ex)
            {
                ipc.Dispose();
                if (!_connectFailureLogged) Log.Write("Discord status unavailable: " + ex.Message);
                _connectFailureLogged = true;
                _nextConnect = DateTime.UtcNow.AddSeconds(ReconnectSeconds);
            }
            finally
            {
                _connecting = false;
            }
        }

        void Disconnect()
        {
            _ipc?.Dispose();
            _ipc = null;
            _shownKey = null;
            _nextConnect = DateTime.UtcNow.AddSeconds(ReconnectSeconds);
        }

        public void Dispose() => Disconnect();
    }
}
