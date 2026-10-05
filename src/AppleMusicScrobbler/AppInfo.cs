using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;

namespace AppleMusicScrobbler
{
    static class AppInfo
    {
        public const string Name = "Apple Music Scrobbler";

        public static Version VersionNumber => Assembly.GetExecutingAssembly().GetName().Version;
        public static string Version => VersionNumber.ToString(3);

        public static string DataFolder =>
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "AppleMusicScrobbler");

        /// <summary>API key compiled in with -p:LastFmApiKey=..., or empty.</summary>
        public static string BuiltInApiKey => Metadata("LastFmApiKey");
        public static string BuiltInApiSecret => Metadata("LastFmApiSecret");

        /// <summary>"owner/repo" this exe was released from (set by the release workflow), or empty for local builds.</summary>
        public static string GitHubRepo => Metadata("GitHubRepo");
        /// <summary>Discord application ID used for the "Listening to" status, or empty to disable it.</summary>
        public static string DiscordClientId => Metadata("DiscordClientId");

        public static string RepoUrl =>GitHubRepo.Length > 0 ? "https://github.com/" + GitHubRepo : "";

        static string Metadata(string key) =>
            Assembly.GetExecutingAssembly().GetCustomAttributes<AssemblyMetadataAttribute>()
                .FirstOrDefault(a => a.Key == key)?.Value ?? "";

        public static void OpenUrl(string url)
        {
            try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
            catch (Exception ex) { Log.Write("Could not open " + url + ": " + ex.Message); }
        }
    }
}
