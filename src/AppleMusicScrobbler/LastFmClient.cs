using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using System.Xml.Linq;

namespace AppleMusicScrobbler
{
    public class LastFmException : Exception
    {
        /// <summary>Last.fm error code (https://www.last.fm/api/errorcodes), 0 if the response wasn't understood.</summary>
        public int Code { get; }

        public LastFmException(int code, string message)
            : base(code > 0 ? $"{message} (Last.fm error {code})" : message)
        {
            Code = code;
        }

        /// <summary>Session or API key no longer valid: the user needs to reconnect.</summary>
        public bool IsAuthProblem => Code == 4 || Code == 9 || Code == 10 || Code == 26;

        /// <summary>Last.fm is down or busy: try again later.</summary>
        public bool IsTemporary => Code == 0 || Code == 8 || Code == 11 || Code == 16 || Code == 29;
    }

    /// <summary>Minimal client for the Last.fm 2.0 API (https://www.last.fm/api).</summary>
    public class LastFmClient
    {
        const string ApiUrl = "https://ws.audioscrobbler.com/2.0/";

        readonly Settings _settings;

        public LastFmClient(Settings settings)
        {
            _settings = settings;
        }

        public async Task<string> GetTokenAsync()
        {
            var response = await CallAsync("auth.getToken", null, withSession: false);
            return (string)response.Element("token");
        }

        /// <summary>The page where the user approves this app for their account.</summary>
        public string GetAuthUrl(string token) =>
            "https://www.last.fm/api/auth/?api_key=" + Uri.EscapeDataString(_settings.EffectiveApiKey) +
            "&token=" + Uri.EscapeDataString(token);

        /// <summary>Throws LastFmException code 14 until the user has approved the token.</summary>
        public async Task<(string Key, string Username)> GetSessionAsync(string token)
        {
            var response = await CallAsync("auth.getSession", new Dictionary<string, string> { ["token"] = token }, withSession: false);
            var session = response.Element("session");
            return ((string)session.Element("key"), (string)session.Element("name"));
        }

        public Task UpdateNowPlayingAsync(NowPlaying track) =>
            CallAsync("track.updateNowPlaying", new Dictionary<string, string>
            {
                ["artist"] = track.Artist,
                ["track"] = track.Title,
                ["album"] = track.Album,
                ["duration"] = track.Duration > 0 ? track.Duration.ToString() : null,
            }, withSession: true);

        public Task LoveAsync(string artist, string title) =>
            CallAsync("track.love", new Dictionary<string, string> { ["artist"] = artist, ["track"] = title }, withSession: true);

        /// <summary>Sends up to 50 scrobbles. Returns a description of each one Last.fm accepted but ignored.</summary>
        public async Task<List<string>> ScrobbleAsync(IList<QueuedScrobble> batch)
        {
            var args = new Dictionary<string, string>();
            for (int i = 0; i < batch.Count; i++)
            {
                var s = batch[i];
                args[$"artist[{i}]"] = s.Artist;
                args[$"track[{i}]"] = s.Track;
                args[$"timestamp[{i}]"] = s.Timestamp.ToString();
                args[$"album[{i}]"] = s.Album;
                if (s.Duration > 0) args[$"duration[{i}]"] = s.Duration.ToString();
            }

            var response = await CallAsync("track.scrobble", args, withSession: true);

            var ignored = new List<string>();
            foreach (var scrobble in response.Element("scrobbles")?.Elements("scrobble") ?? Enumerable.Empty<XElement>())
            {
                var message = scrobble.Element("ignoredMessage");
                string code = (string)message?.Attribute("code");
                if (!string.IsNullOrEmpty(code) && code != "0")
                    ignored.Add($"{(string)scrobble.Element("artist")} - {(string)scrobble.Element("track")} (reason {code}: {IgnoredReason(code)})");
            }
            return ignored;
        }

        static string IgnoredReason(string code)
        {
            switch (code)
            {
                case "1": return "artist ignored";
                case "2": return "track ignored";
                case "3": return "timestamp too old";
                case "4": return "timestamp too new";
                case "5": return "daily scrobble limit reached";
                default: return "unknown";
            }
        }

        async Task<XElement> CallAsync(string method, IDictionary<string, string> args, bool withSession)
        {
            var parameters = new SortedDictionary<string, string>(StringComparer.Ordinal)
            {
                ["method"] = method,
                ["api_key"] = _settings.EffectiveApiKey,
            };
            if (withSession) parameters["sk"] = _settings.SessionKey;
            if (args != null)
                foreach (var kv in args)
                    if (!string.IsNullOrEmpty(kv.Value)) parameters[kv.Key] = kv.Value;

            parameters["api_sig"] = Sign(parameters, _settings.EffectiveApiSecret);

            HttpResponseMessage httpResponse;
            using (var content = new FormUrlEncodedContent(parameters))
                httpResponse = await Http.Client.PostAsync(ApiUrl, content);

            using (httpResponse)
            {
                byte[] body = await httpResponse.Content.ReadAsByteArrayAsync();
                XElement root;
                try
                {
                    root = XElement.Parse(Encoding.UTF8.GetString(body).TrimStart('﻿'));
                }
                catch
                {
                    throw new LastFmException(0, $"Unexpected response from Last.fm (HTTP {(int)httpResponse.StatusCode})");
                }

                if ((string)root.Attribute("status") == "ok") return root;

                var error = root.Element("error");
                throw new LastFmException((int?)error?.Attribute("code") ?? 0, error?.Value.Trim() ?? "Unknown Last.fm error");
            }
        }

        /// <summary>
        /// Last.fm request signature: every parameter as name+value, sorted by name (ordinal),
        /// followed by the shared secret, MD5-hashed as UTF-8.
        /// </summary>
        internal static string Sign(IEnumerable<KeyValuePair<string, string>> parameters, string secret)
        {
            var toSign = new StringBuilder();
            foreach (var kv in parameters.OrderBy(p => p.Key, StringComparer.Ordinal))
                toSign.Append(kv.Key).Append(kv.Value);
            toSign.Append(secret);
            return Md5Hex(toSign.ToString());
        }

        static string Md5Hex(string text)
        {
            using (var md5 = MD5.Create())
                return string.Concat(md5.ComputeHash(Encoding.UTF8.GetBytes(text)).Select(b => b.ToString("x2")));
        }
    }
}
