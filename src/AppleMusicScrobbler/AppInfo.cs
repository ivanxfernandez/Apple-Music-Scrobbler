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

        public static string Version => Assembly.GetExecutingAssembly().GetName().Version.ToString(3);

        public static string DataFolder =>
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "AppleMusicScrobbler");

        /// <summary>API key compiled in with -p:LastFmApiKey=..., or empty.</summary>
        public static string BuiltInApiKey => Metadata("LastFmApiKey");
        public static string BuiltInApiSecret => Metadata("LastFmApiSecret");

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
