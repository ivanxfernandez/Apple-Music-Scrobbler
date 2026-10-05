using System;
using System.IO;
using System.Linq;
using Microsoft.Win32;

namespace AppleMusicScrobbler
{
    /// <summary>
    /// Builds the "Report a problem" link: a new GitHub issue with the bug form's fields filled in
    /// (version, system, recent log lines). The user sees and edits it before submitting.
    /// Same rules as macos/Sources/ScrobblerCore/IssueReport.swift.
    /// </summary>
    public static class IssueReport
    {
        /// <summary>The project's repository; local builds without GitHubRepo report here too.</summary>
        public const string DefaultRepo = "ivanxfernandez/Apple-Music-Scrobbler";
        /// <summary>GitHub rejects very long URLs, so only the end of the log is included.</summary>
        public const int MaxLogLines = 30;
        public const int MaxLogCharacters = 4000;

        public static string Url(string repo, string version, string system, string log)
        {
            string query = string.Join("&",
                "template=bug_report.yml",
                "version=" + Uri.EscapeDataString(version ?? ""),
                "system=" + Uri.EscapeDataString(system ?? ""),
                "log=" + Uri.EscapeDataString(LogTail(log)));
            return "https://github.com/" + (string.IsNullOrEmpty(repo) ? DefaultRepo : repo) + "/issues/new?" + query;
        }

        /// <summary>The last lines of the log, at most MaxLogLines and MaxLogCharacters (cut at a line break).</summary>
        public static string LogTail(string log)
        {
            var lines = (log ?? "").Replace("\r\n", "\n").Split('\n').ToList();
            while (lines.Count > 0 && lines[lines.Count - 1].Length == 0) lines.RemoveAt(lines.Count - 1);
            var tail = lines.Skip(Math.Max(0, lines.Count - MaxLogLines)).ToList();
            while (tail.Count > 1 && string.Join("\n", tail).Length > MaxLogCharacters) tail.RemoveAt(0);
            string text = string.Join("\n", tail);
            return text.Length > MaxLogCharacters ? text.Substring(text.Length - MaxLogCharacters) : text;
        }

        /// <summary>"Windows 11 24H2 (build 26100)". Windows 11 still calls itself 10.0, so the build number decides.</summary>
        public static string SystemDescription()
        {
            try
            {
                using (var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion"))
                {
                    int.TryParse(key?.GetValue("CurrentBuild") as string, out int build);
                    string release = key?.GetValue("DisplayVersion") as string ?? "";
                    string name = build >= 22000 ? "Windows 11" : "Windows 10";
                    return $"{name} {release} (build {build})".Replace("  ", " ");
                }
            }
            catch
            {
                return Environment.OSVersion.VersionString;
            }
        }

        /// <summary>The log file's text, read without blocking the app from writing to it.</summary>
        public static string ReadLog()
        {
            try
            {
                using (var stream = new FileStream(Log.FilePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                using (var reader = new StreamReader(stream))
                    return reader.ReadToEnd();
            }
            catch
            {
                return "";
            }
        }
    }
}
