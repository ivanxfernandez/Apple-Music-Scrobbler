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
        /// <summary>The release page.</summary>
        public string Url { get; set; }
        /// <summary>The exe's download URL, or null if the release has none with a SHA-256 to check it against.</summary>
        public string DownloadUrl { get; set; }
        /// <summary>Lowercase hex SHA-256 of the download, from GitHub's asset digest.</summary>
        public string Sha256 { get; set; }
    }

    /// <summary>Checks the GitHub repository the exe was built from for a newer release.</summary>
    public static class UpdateChecker
    {
        /// <summary>The Windows app's file in each release (see release.yml).</summary>
        public const string WindowsAssetName = "AppleMusicScrobbler.exe";

        /// <summary>For --pretend-version: check for updates as if this were an older version (to test the updater).</summary>
        public static Version PretendVersion { get; set; }

        [DataContract]
        public class GitHubAsset
        {
            [DataMember(Name = "name")] public string Name { get; set; }
            [DataMember(Name = "browser_download_url")] public string DownloadUrl { get; set; }
            [DataMember(Name = "digest")] public string Digest { get; set; }
        }

        [DataContract]
        public class GitHubRelease
        {
            [DataMember(Name = "tag_name")] public string TagName { get; set; }
            [DataMember(Name = "html_url")] public string HtmlUrl { get; set; }
            [DataMember(Name = "draft")] public bool Draft { get; set; }
            [DataMember(Name = "prerelease")] public bool Prerelease { get; set; }
            [DataMember(Name = "assets")] public GitHubAsset[] Assets { get; set; }
        }

        public static GitHubRelease ParseRelease(byte[] json) =>
            (GitHubRelease)new DataContractJsonSerializer(typeof(GitHubRelease)).ReadObject(new MemoryStream(json));

        /// <summary>The named file of a release, if it has an https download URL and a SHA-256 digest.</summary>
        public static GitHubAsset FindAsset(GitHubRelease release, string name)
        {
            foreach (var asset in release?.Assets ?? new GitHubAsset[0])
                if (asset.Name == name && (asset.DownloadUrl ?? "").StartsWith("https://", StringComparison.Ordinal) && Sha256FromDigest(asset.Digest) != null)
                    return asset;
            return null;
        }

        /// <summary>"sha256:ABC…" → "abc…"; null for anything else.</summary>
        public static string Sha256FromDigest(string digest)
        {
            if (digest == null || !digest.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase)) return null;
            string hex = digest.Substring(7).ToLowerInvariant();
            if (hex.Length != 64) return null;
            foreach (char c in hex)
                if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) return null;
            return hex;
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
                var release = ParseRelease(body);

                if (release.Draft || release.Prerelease || !TryParseVersion(release.TagName, out var latest)) return null;
                if (!IsNewer(latest, PretendVersion ?? AppInfo.VersionNumber)) return null;
                var asset = FindAsset(release, WindowsAssetName);
                return new ReleaseInfo
                {
                    Version = latest,
                    Tag = release.TagName,
                    Url = release.HtmlUrl,
                    DownloadUrl = asset?.DownloadUrl,
                    Sha256 = Sha256FromDigest(asset?.Digest),
                };
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
