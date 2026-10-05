using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using Xunit;

namespace AppleMusicScrobbler.Tests
{
    public class LocalizationTests
    {
        /// <summary>Every L("…") in the app's code, with C# escapes (\" \\ \n) turned into the real characters.</summary>
        static HashSet<string> KeysUsedInCode()
        {
            var dir = new DirectoryInfo(AppDomain.CurrentDomain.BaseDirectory);
            while (dir != null && !File.Exists(Path.Combine(dir.FullName, "AppleMusicScrobbler.sln"))) dir = dir.Parent;
            Assert.NotNull(dir);
            var pattern = new Regex(@"\bL\(""((?:[^""\\]|\\.)*)""");
            var keys = new HashSet<string>();
            foreach (var file in Directory.GetFiles(Path.Combine(dir.FullName, "src", "AppleMusicScrobbler"), "*.cs", SearchOption.AllDirectories))
            {
                if (Path.GetFileName(file) == "Localization.cs") continue;
                foreach (Match m in pattern.Matches(File.ReadAllText(file, Encoding.UTF8)))
                    keys.Add(Unescape(m.Groups[1].Value));
            }
            return keys;
        }

        static string Unescape(string literal)
        {
            var sb = new StringBuilder();
            for (int i = 0; i < literal.Length; i++)
            {
                char c = literal[i];
                if (c != '\\' || i + 1 >= literal.Length) { sb.Append(c); continue; }
                char next = literal[++i];
                sb.Append(next == 'n' ? '\n' : next == 't' ? '\t' : next);
            }
            return sb.ToString();
        }

        static int Placeholders(string s) => Regex.Matches(s, @"\{\d+\}").Cast<Match>().Select(m => m.Value).Distinct().Count();

        [Fact]
        public void Every_text_in_the_app_has_a_Spanish_translation()
        {
            var keys = KeysUsedInCode();
            Assert.True(keys.Count > 60, $"only {keys.Count} L(\"…\") calls found");
            var missing = keys.Where(k => !Localization.Spanish.ContainsKey(k)).OrderBy(k => k).ToList();
            Assert.True(missing.Count == 0, "Missing Spanish for: " + string.Join(" | ", missing));
        }

        [Fact]
        public void Translations_keep_the_placeholders()
        {
            foreach (var pair in Localization.Spanish)
                Assert.True(Placeholders(pair.Key) == Placeholders(pair.Value), pair.Key);
        }

        [Fact]
        public void No_unused_translations()
        {
            var keys = KeysUsedInCode();
            var unused = Localization.Spanish.Keys.Where(k => !keys.Contains(k)).OrderBy(k => k).ToList();
            Assert.True(unused.Count == 0, "Not used in the code: " + string.Join(" | ", unused));
        }

        [Fact]
        public void Picks_the_language_from_the_display_culture()
        {
            Assert.Equal("es", Localization.Detect(CultureInfo.GetCultureInfo("es-MX")));
            Assert.Equal("en", Localization.Detect(CultureInfo.GetCultureInfo("en-US")));
            Assert.Equal("en", Localization.Detect(CultureInfo.GetCultureInfo("fr-FR")));
        }
    }
}
