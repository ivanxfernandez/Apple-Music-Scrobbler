using System;
using System.Linq;
using System.Net;
using System.Threading;
using System.Windows.Forms;

namespace AppleMusicScrobbler
{
    static class Program
    {
        /// <summary>--dry-run: read Apple Music and log what would be scrobbled, without contacting Last.fm.</summary>
        public static bool DryRun { get; private set; }

        /// <summary>--open-menu: open the tray menu a few seconds after starting (used by tools/screenshots.ps1).</summary>
        public static bool OpenMenuOnStart { get; private set; }

        [STAThread]
        static void Main(string[] args)
        {
            bool HasFlag(string flag) => args.Any(a => a.Equals(flag, StringComparison.OrdinalIgnoreCase));
            DryRun = HasFlag("--dry-run");
            OpenMenuOnStart = HasFlag("--open-menu");

            // --pretend-version X.Y.Z: check for updates as if this were version X.Y.Z, to test the
            // updater against the latest release (it offers to "update" to it).
            int pretend = Array.FindIndex(args, a => a.Equals("--pretend-version", StringComparison.OrdinalIgnoreCase));
            if (pretend >= 0 && pretend + 1 < args.Length && UpdateChecker.TryParseVersion(args[pretend + 1], out var pretendVersion))
                UpdateChecker.PretendVersion = pretendVersion;

            // --language es: show the app in that language (to review a translation); default: Windows' display language.
            int language = Array.FindIndex(args, a => a.Equals("--language", StringComparison.OrdinalIgnoreCase));
            if (language >= 0 && language + 1 < args.Length) Localization.Language = args[language + 1].ToLowerInvariant();

            // After a one-click update: wait for the previous version to exit, delete its exe.
            Updater.FinishUpdate(args);

            if (HasFlag("--show-setup"))
            {
                // Preview of the first-run window (used by tools/screenshots.ps1); doesn't touch the running app.
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                using (var setup = new SetupForm(new Settings())) setup.ShowDialog();
                return;
            }

            using (var mutex = new Mutex(true, @"Local\AppleMusicScrobbler", out bool firstInstance))
            {
                if (!firstInstance)
                {
                    MessageBox.Show(Localization.L("Apple Music Scrobbler is already running.\n\nLook for the red note icon in the system tray (you may need to click the ^ arrow)."),
                        AppInfo.Name, MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }

                ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);

                var settings = Settings.Load();
                bool justConnected = false;
                if (!DryRun && !settings.IsConnected)
                {
                    using (var setup = new SetupForm(settings))
                    {
                        if (setup.ShowDialog() != DialogResult.OK) return;
                    }
                    justConnected = true;
                }

                Application.Run(new TrayApp(settings, justConnected));
            }
        }
    }
}
