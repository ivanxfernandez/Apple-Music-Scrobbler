using System;
using System.IO;
using System.Net.Http;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Threading.Tasks;

namespace AppleMusicScrobbler
{
    public class ReleaseInfo
    {
        public Version Version { get; set; }
        public string Tag { get; set; }
        public string Url { get; set; }
    }

    /// <summary>Checks the GitHub repository the exe was built from for a newer release.</summary>
    public static class UpdateChecker
    {
        [DataContract]
        class GitHubRelease
        {
            [DataMember(Name = "tag_name")] public string TagName { get; set; }
            [DataMember(Name = "html_url")] public string HtmlUrl { get; set; }
            [DataMember(Name = "draft")] public bool Draft { get; set; }
            [DataMember(Name = "prerelease")] public bool Prerelease { get; set; }
        }

        /// <summary>The latest release if it's newer than this exe; null otherwise or when the exe isn't a release build.</summary>
        public static async Task<ReleaseInfo> GetNewerReleaseAsync()
        {
            if (string.IsNullOrEmpty(AppInfo.GitHubRepo)) return null;

            var request = new HttpRequestMessage(HttpMethod.Get, $"https://api.github.com/repos/{AppInfo.GitHubRepo}/releases/latest");
            request.Headers.Accept.ParseAdd("application/vnd.github+json");
            using (var response = await Http.Client.SendAsync(request))
            {
                if (!response.IsSuccessStatusCode) return null; // 404 = no releases yet
                byte[] body = await response.Content.ReadAsByteArrayAsync();
                var release = (GitHubRelease)new DataContractJsonSerializer(typeof(GitHubRelease)).ReadObject(new MemoryStream(body));

                if (release.Draft || release.Prerelease || !TryParseVersion(release.TagName, out var latest)) return null;
                if (!IsNewer(latest, AppInfo.VersionNumber)) return null;
                return new ReleaseInfo { Version = latest, Tag = release.TagName, Url = release.HtmlUrl };
            }
        }

        /// <summary>Parses tags like "v1.2.0", "1.2" or "v1.2.0-beta.1" (suffix ignored).</summary>
        public static bool TryParseVersion(string tag, out Version version)
        {
            version = null;
            if (string.IsNullOrWhiteSpace(tag)) return false;
            string s = tag.Trim().TrimStart('v', 'V');
            int cut = s.IndexOfAny(new[] { '-', '+' });
            if (cut >= 0) s = s.Substring(0, cut);
            if (!Version.TryParse(s.Contains(".") ? s : s + ".0", out var parsed)) return false;
            version = Normalize(parsed);
            return true;
        }

        public static bool IsNewer(Version candidate, Version current) => Normalize(candidate) > Normalize(current);

        // 1.2 == 1.2.0 == 1.2.0.0
        static Version Normalize(Version v) => new Version(v.Major, v.Minor, Math.Max(0, v.Build));
    }
}
