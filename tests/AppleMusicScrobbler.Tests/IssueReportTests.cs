using System;
using System.Linq;
using Xunit;

namespace AppleMusicScrobbler.Tests
{
    public class IssueReportTests
    {
        static string Query(string url, string name)
        {
            string query = url.Substring(url.IndexOf('?') + 1);
            var pair = query.Split('&').Select(p => p.Split(new[] { '=' }, 2)).First(p => p[0] == name);
            return Uri.UnescapeDataString(pair[1]);
        }

        [Fact]
        public void Prefills_the_bug_form_fields()
        {
            string url = IssueReport.Url("owner/repo", "1.4.0", "Windows 11 24H2", "line 1\r\nline & 2\r\n");
            Assert.StartsWith("https://github.com/owner/repo/issues/new?", url);
            Assert.Equal("bug_report.yml", Query(url, "template"));
            Assert.Equal("1.4.0", Query(url, "version"));
            Assert.Equal("Windows 11 24H2", Query(url, "system"));
            Assert.Equal("line 1\nline & 2", Query(url, "log"));
        }

        [Fact]
        public void Local_builds_report_to_the_project_repo() =>
            Assert.StartsWith("https://github.com/ivanxfernandez/Apple-Music-Scrobbler/issues/new?", IssueReport.Url("", "1", "x", ""));

        [Fact]
        public void Keeps_only_the_end_of_the_log()
        {
            string log = string.Join("\r\n", Enumerable.Range(1, 100).Select(i => "line " + i)) + "\r\n";
            string tail = IssueReport.LogTail(log);
            Assert.StartsWith("line 71\n", tail);
            Assert.EndsWith("line 100", tail);
            Assert.DoesNotContain("\r", tail);
        }

        [Fact]
        public void Caps_the_log_length()
        {
            string log = string.Join("\n", Enumerable.Range(1, 30).Select(_ => new string('x', 300)));
            string tail = IssueReport.LogTail(log);
            Assert.True(tail.Length <= IssueReport.MaxLogCharacters);
            Assert.StartsWith("x", tail);
            Assert.Equal("", IssueReport.LogTail(""));
            Assert.Equal("", IssueReport.LogTail(null));
        }
    }
}
