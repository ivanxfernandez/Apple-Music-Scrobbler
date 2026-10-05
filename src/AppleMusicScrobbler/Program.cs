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
                    MessageBox.Show("Apple Music Scrobbler is already running.\n\nLook for the red note icon in the system tray (you may need to click the ^ arrow).",
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
