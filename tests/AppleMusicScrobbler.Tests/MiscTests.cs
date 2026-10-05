using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using Xunit;

namespace AppleMusicScrobbler.Tests
{
    public class UpdateCheckerTests
    {
        [Theory]
        [InlineData("v1.2.0", "1.2.0")]
        [InlineData("1.2", "1.2.0")]
        [InlineData("V2", "2.0.0")]
        [InlineData("v1.2.0-beta.1", "1.2.0")]
        [InlineData("v1.2.3+build.7", "1.2.3")]
        public void Parses_release_tags(string tag, string expected)
        {
            Assert.True(UpdateChecker.TryParseVersion(tag, out var version));
            Assert.Equal(Version.Parse(expected), version);
        }

        [Theory]
        [InlineData("")]
        [InlineData(null)]
        [InlineData("nightly")]
        [InlineData("v")]
        public void Rejects_non_version_tags(string tag) =>
            Assert.False(UpdateChecker.TryParseVersion(tag, out _));

        [Theory]
        [InlineData("1.2.0", "1.1.9.0", true)]
        [InlineData("1.10.0", "1.9.0.0", true)]
        [InlineData("1.2", "1.2.0.0", false)]
        [InlineData("1.1.0", "1.2.0.0", false)]
        public void Compares_versions(string candidate, string current, bool newer) =>
            Assert.Equal(newer, UpdateChecker.IsNewer(Version.Parse(candidate), Version.Parse(current)));
    }

    public class ReleaseAssetTests
    {
        const string Hash = "a1b4b34c5be87421980a95fd8973d38bb76cdb0cd3e96aeb90314de8059a6e10";

        [Fact]
        public void Reads_GitHub_digests()
        {
            Assert.Equal(Hash, UpdateChecker.Sha256FromDigest("sha256:" + Hash.ToUpperInvariant()));
            Assert.Null(UpdateChecker.Sha256FromDigest("sha256:abc"));
            Assert.Null(UpdateChecker.Sha256FromDigest("md5:" + Hash));
            Assert.Null(UpdateChecker.Sha256FromDigest("sha256:" + new string('g', 64)));
            Assert.Null(UpdateChecker.Sha256FromDigest(null));
        }

        [Fact]
        public void Picks_the_exe_with_its_digest()
        {
            string json = "{\"tag_name\":\"v1.3.0\",\"assets\":[" +
                "{\"name\":\"AppleMusicScrobbler-macOS.zip\",\"browser_download_url\":\"https://github.com/o/r/releases/download/v1.3.0/AppleMusicScrobbler-macOS.zip\",\"digest\":\"sha256:" + new string('b', 64) + "\"}," +
                "{\"name\":\"AppleMusicScrobbler.exe\",\"browser_download_url\":\"https://github.com/o/r/releases/download/v1.3.0/AppleMusicScrobbler.exe\",\"digest\":\"sha256:" + Hash + "\"}]}";
            var release = UpdateChecker.ParseRelease(System.Text.Encoding.UTF8.GetBytes(json));
            var asset = UpdateChecker.FindAsset(release, UpdateChecker.WindowsAssetName);
            Assert.NotNull(asset);
            Assert.EndsWith("/AppleMusicScrobbler.exe", asset.DownloadUrl);
            Assert.Equal(Hash, UpdateChecker.Sha256FromDigest(asset.Digest));
        }

        [Fact]
        public void Ignores_assets_without_a_digest()
        {
            string json = "{\"assets\":[{\"name\":\"AppleMusicScrobbler.exe\",\"browser_download_url\":\"https://x/y.exe\"}]}";
            Assert.Null(UpdateChecker.FindAsset(UpdateChecker.ParseRelease(System.Text.Encoding.UTF8.GetBytes(json)), UpdateChecker.WindowsAssetName));
            Assert.Null(UpdateChecker.FindAsset(UpdateChecker.ParseRelease(System.Text.Encoding.UTF8.GetBytes("{}")), UpdateChecker.WindowsAssetName));
        }
    }

    public class LastFmSignatureTests
    {
        static string Md5(string s) =>
            string.Concat(MD5.Create().ComputeHash(Encoding.UTF8.GetBytes(s)).Select(b => b.ToString("x2")));

        [Fact]
        public void Signs_parameters_sorted_by_name_then_secret()
        {
            var parameters = new Dictionary<string, string>
            {
                ["track[0]"] = "Song",
                ["method"] = "track.scrobble",
                ["artist[0]"] = "Artist",
                ["api_key"] = "KEY",
                ["sk"] = "SESSION",
                ["album[0]"] = "Album",
            };
            string expected = Md5("album[0]Album" + "api_keyKEY" + "artist[0]Artist" + "methodtrack.scrobble" + "skSESSION" + "track[0]Song" + "SECRET");
            Assert.Equal(expected, LastFmClient.Sign(parameters, "SECRET"));
        }

        [Fact]
        public void Signs_non_ascii_as_utf8()
        {
            var parameters = new Dictionary<string, string> { ["artist"] = "Молчат Дома", ["track"] = "Судно" };
            Assert.Equal(Md5("artistМолчат ДомаtrackСудноS"), LastFmClient.Sign(parameters, "S"));
        }

        [Fact]
        public void Matches_known_md5()
        {
            // md5("abc") is a standard test vector
            Assert.Equal("900150983cd24fb0d6963f7d28e17f72", LastFmClient.Sign(new Dictionary<string, string>(), "abc"));
        }
    }
}
