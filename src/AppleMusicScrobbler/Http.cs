using System;
using System.Net.Http;

namespace AppleMusicScrobbler
{
    static class Http
    {
        /// <summary>One shared client for the whole app (Last.fm and GitHub).</summary>
        public static readonly HttpClient Client = Create();

        static HttpClient Create()
        {
            var client = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
            client.DefaultRequestHeaders.UserAgent.ParseAdd("AppleMusicScrobbler/" + AppInfo.Version);
            return client;
        }
    }
}
