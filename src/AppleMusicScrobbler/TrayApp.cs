using System;
using System.Diagnostics;
using System.Drawing;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows.Forms;
using AppleMusicScrobbler.Discord;

namespace AppleMusicScrobbler
{
    /// <summary>The tray icon and its menu; polls Apple Music once a second.</summary>
    public class TrayApp : ApplicationContext
    {
        const int UpdateCheckIntervalMs = 24 * 60 * 60 * 1000;

        readonly Settings _settings;
        readonly LastFmClient _api;
        readonly MediaReader _reader = new MediaReader();
        readonly Scrobbler _scrobbler;
        readonly DiscordPresence _discord;

        readonly NotifyIcon _tray;
        readonly Timer _timer;
        readonly Timer _updateTimer;
        readonly Icon _iconActive, _iconPaused;
        readonly ToolStripMenuItem _nowItem, _lastItem, _recentItem, _updateItem, _loveItem, _pauseItem;
        readonly ToolStripMenuItem _startupItem, _checkUpdatesItem, _discordItem;

        bool _busy;
        bool _authWarningShown;
        string _lastError;
        string _balloonUrl;
        bool _balloonInstallsUpdate;
        bool _installing;
        ReleaseInfo _update;

        public TrayApp(Settings settings, bool justConnected)
        {
            _settings = settings;
            _api = new LastFmClient(settings);
            _scrobbler = new Scrobbler(settings, _api, Program.DryRun);
            _scrobbler.AuthProblem += OnAuthProblem;
            _discord = new DiscordPresence(settings);

            int iconSize = SystemInformation.SmallIconSize.Width;
            _iconActive = IconFactory.CreateIcon(IconFactory.Red, iconSize);
            _iconPaused = IconFactory.CreateIcon(IconFactory.Grey, iconSize);

            _nowItem = new ToolStripMenuItem("Nothing playing") { Enabled = false };
            _lastItem = new ToolStripMenuItem("Nothing scrobbled yet") { Enabled = false };
            _recentItem = new ToolStripMenuItem("Recent scrobbles");
            _recentItem.DropDownItems.Add("Nothing scrobbled yet"); // placeholder so the arrow shows; filled when opened
            _recentItem.DropDownOpening += (s, e) => BuildRecentMenu();
            _updateItem = new ToolStripMenuItem("Update available", null, (s, e) => OfferUpdate()) { Visible = false };
            _updateItem.Font = new Font(_updateItem.Font, FontStyle.Bold);
            _loveItem = new ToolStripMenuItem("♥ Love this song on Last.fm", null, async (s, e) => await LoveCurrentAsync());
            _pauseItem = new ToolStripMenuItem("Pause scrobbling", null, (s, e) => TogglePause()) { Checked = settings.Paused };

            _startupItem = new ToolStripMenuItem("Start with Windows", null, (s, e) => ToggleStartup()) { Checked = Startup.IsEnabled };
            _checkUpdatesItem = new ToolStripMenuItem("Check for updates automatically", null, (s, e) => ToggleUpdateChecks())
            {
                Checked = settings.CheckForUpdates,
                Visible = AppInfo.GitHubRepo.Length > 0,
            };
            var options = new ToolStripMenuItem("Options");
            var cleanItem = new ToolStripMenuItem("Clean up titles (remove “Remaster”, “- Single”…)")
            {
                Checked = settings.CleanTitles,
                ToolTipText = "“Song [2022 Remaster]” is scrobbled as “Song”, “Album (Deluxe Edition)” as “Album”",
            };
            cleanItem.Click += (s, e) =>
            {
                _settings.CleanTitles = !_settings.CleanTitles;
                cleanItem.Checked = _settings.CleanTitles;
                SaveSettings();
            };
            var mainArtistItem = new ToolStripMenuItem("Scrobble only the main artist of collaborations")
            {
                Checked = settings.MainArtistOnly,
                ToolTipText = "“Joji & BENEE” is scrobbled as “Joji”. Bands like “Simon & Garfunkel” are left alone (Last.fm's listener counts tell them apart).",
            };
            mainArtistItem.Click += (s, e) =>
            {
                _settings.MainArtistOnly = !_settings.MainArtistOnly;
                mainArtistItem.Checked = _settings.MainArtistOnly;
                SaveSettings();
                Log.Write(_settings.MainArtistOnly ? "Scrobbling only the main artist of collaborations" : "Scrobbling full artist credits");
            };
            _discordItem = new ToolStripMenuItem("Show “Listening to” on Discord", null, (s, e) => ToggleDiscord())
            {
                Checked = settings.ShowOnDiscord,
                Visible = DiscordPresence.Available,
            };
            options.DropDownItems.AddRange(new ToolStripItem[]
            {
                _startupItem,
                _discordItem,
                cleanItem,
                mainArtistItem,
                _checkUpdatesItem,
                new ToolStripSeparator(),
                new ToolStripMenuItem("Switch Last.fm account...", null, (s, e) => Reconnect()),
                new ToolStripMenuItem("Open log", null, (s, e) => OpenLog()),
            });

            var menu = new ContextMenuStrip();
            menu.Items.AddRange(new ToolStripItem[]
            {
                _nowItem,
                _lastItem,
                _recentItem,
                new ToolStripSeparator(),
                _updateItem,
                _loveItem,
                _pauseItem,
                new ToolStripMenuItem("Open my Last.fm profile", null, (s, e) => AppInfo.OpenUrl("https://www.last.fm/user/" + Uri.EscapeDataString(_settings.Username ?? ""))),
                options,
                new ToolStripSeparator(),
                new ToolStripMenuItem("Report a problem...", null, (s, e) => ReportProblem()),
                new ToolStripMenuItem($"About {AppInfo.Name}", null, (s, e) => ShowAbout()),
                new ToolStripMenuItem("Quit", null, (s, e) => ExitThread()),
            });

            _tray = new NotifyIcon
            {
                Icon = settings.Paused ? _iconPaused : _iconActive,
                Text = AppInfo.Name,
                ContextMenuStrip = menu,
                Visible = true,
            };
            // Left-click opens the menu too.
            _tray.MouseUp += (s, e) =>
            {
                if (e.Button == MouseButtons.Left) OpenMenu();
            };
            _tray.BalloonTipClicked += (s, e) =>
            {
                if (_balloonInstallsUpdate) OfferUpdate();
                else if (_balloonUrl != null) AppInfo.OpenUrl(_balloonUrl);
            };
            _tray.BalloonTipClosed += (s, e) => { _balloonUrl = null; _balloonInstallsUpdate = false; };

            _timer = new Timer { Interval = 1000 };
            _timer.Tick += OnTick;
            _timer.Start();

            // First update check a minute after starting (right away when testing the updater), then daily.
            _updateTimer = new Timer { Interval = UpdateChecker.PretendVersion == null ? 60 * 1000 : 3000 };
            _updateTimer.Tick += async (s, e) =>
            {
                _updateTimer.Interval = UpdateCheckIntervalMs;
                await CheckForUpdateAsync(manual: false);
            };
            if (AppInfo.GitHubRepo.Length > 0) _updateTimer.Start();

            if (Program.OpenMenuOnStart)
            {
                var openMenu = new Timer { Interval = 4000 };
                openMenu.Tick += (s, e) => { openMenu.Dispose(); OpenMenu(); };
                openMenu.Start();
            }

            Log.Write(Program.DryRun
                ? $"Started {AppInfo.Version} (dry run: nothing is sent to Last.fm)"
                : $"Started {AppInfo.Version}, scrobbling as {_settings.Username}");

            if (_settings.LastRunVersion.Length > 0 && _settings.LastRunVersion != AppInfo.Version)
            {
                Log.Write($"Updated from {_settings.LastRunVersion} to {AppInfo.Version}");
                ShowBalloon($"Updated to {AppInfo.Version}", $"{AppInfo.Name} is up to date. Click to see what's new.", ToolTipIcon.Info,
                    AppInfo.RepoUrl.Length > 0 ? $"{AppInfo.RepoUrl}/releases/tag/v{AppInfo.Version}" : null);
            }
            if (_settings.LastRunVersion != AppInfo.Version)
            {
                _settings.LastRunVersion = AppInfo.Version;
                SaveSettings();
            }

            if (justConnected)
                ShowBalloon("Connected to Last.fm",
                    $"Scrobbling Apple Music as {_settings.Username}. I'll be here in the tray.", ToolTipIcon.Info);
        }

        async void OnTick(object sender, EventArgs e)
        {
            if (_busy) return;
            _busy = true;
            try
            {
                var np = await _reader.ReadAsync();
                _scrobbler.Update(np);
                _discord.Update(_scrobbler.Current); // same (cleaned) track info as Last.fm gets
                _lastError = null;
            }
            catch (Exception ex)
            {
                if (ex.Message != _lastError) Log.Write("Error reading Apple Music: " + ex.Message);
                _lastError = ex.Message;
            }
            finally
            {
                _busy = false;
                UpdateUi();
            }
        }

        void UpdateUi()
        {
            var np = _scrobbler.Current;
            string playing = np != null && np.IsValid ? np.ToString() + (np.IsPlaying ? "" : " (paused)") : "Nothing playing";

            SetText(_nowItem, MenuText(playing));
            SetText(_lastItem, string.IsNullOrEmpty(_scrobbler.LastScrobbled) ? "Nothing scrobbled yet" : MenuText("Last scrobbled: " + _scrobbler.LastScrobbled));
            SetText(_recentItem, _scrobbler.Pending > 0 ? $"Recent scrobbles ({_scrobbler.Pending} waiting)" : "Recent scrobbles");
            _loveItem.Enabled = np != null && np.IsValid && !Program.DryRun;
            SetText(_discordItem, "Show “Listening to” on Discord" +
                (_settings.ShowOnDiscord && !_discord.IsConnected ? " (waiting for Discord)" : ""));

            string tip = (_settings.Paused ? "Scrobbling paused\n" : "") + playing;
            if (_scrobbler.Pending > 0) tip += $"\n{_scrobbler.Pending} waiting to send";
            if (tip.Length > 63) tip = tip.Substring(0, 62) + "…"; // Windows limit
            if (_tray.Text != tip) _tray.Text = tip;
        }

        /// <summary>Latest scrobbles (click one to open it on Last.fm), anything waiting to be sent, and Send now.</summary>
        void BuildRecentMenu()
        {
            var items = _recentItem.DropDownItems;
            items.Clear();
            var recent = _scrobbler.Recent;
            if (recent.Count == 0) items.Add(new ToolStripMenuItem("Nothing scrobbled yet") { Enabled = false });
            foreach (var r in recent)
            {
                string url = r.Url;
                items.Add(new ToolStripMenuItem(MenuText($"{RecentScrobbles.Time(r, DateTime.Now)}   {r.Artist} - {r.Track}"), null,
                    (s, e) => AppInfo.OpenUrl(url)) { ToolTipText = "Open on Last.fm" });
            }

            var pending = _scrobbler.PendingScrobbles;
            if (pending.Count > 0)
            {
                items.Add(new ToolStripSeparator());
                items.Add(new ToolStripMenuItem(pending.Count == 1 ? "1 waiting to send" : $"{pending.Count} waiting to send") { Enabled = false });
                for (int i = pending.Count - 1; i >= Math.Max(0, pending.Count - 5); i--)
                    items.Add(new ToolStripMenuItem(MenuText($"    {pending[i].Artist} - {pending[i].Track}")) { Enabled = false });
                items.Add(new ToolStripMenuItem("Send now", null, (s, e) =>
                {
                    Log.Write($"Sending {_scrobbler.Pending} waiting scrobble(s) now");
                    _scrobbler.RetrySoon();
                }) { Enabled = !Program.DryRun });
            }

            items.Add(new ToolStripSeparator());
            items.Add(new ToolStripMenuItem("Open my Last.fm library", null,
                (s, e) => AppInfo.OpenUrl("https://www.last.fm/user/" + Uri.EscapeDataString(_settings.Username ?? "") + "/library")));
        }

        static string MenuText(string text)
        {
            if (text.Length > 70) text = text.Substring(0, 69) + "…";
            return text.Replace("&", "&&");
        }

        static void SetText(ToolStripItem item, string text)
        {
            if (item.Text != text) item.Text = text;
        }

        public void OpenMenu() =>
            typeof(NotifyIcon).GetMethod("ShowContextMenu", BindingFlags.Instance | BindingFlags.NonPublic)?.Invoke(_tray, null);

        void ShowBalloon(string title, string text, ToolTipIcon icon, string clickUrl = null, bool installsUpdate = false)
        {
            _balloonUrl = clickUrl;
            _balloonInstallsUpdate = installsUpdate;
            _tray.ShowBalloonTip(10000, title, text, icon);
        }

        async Task LoveCurrentAsync()
        {
            var np = _scrobbler.Current;
            if (np == null || !np.IsValid) return;
            try
            {
                await _api.LoveAsync(np.Artist, np.Title);
                Log.Write("Loved: " + np);
                ShowBalloon("♥ Loved on Last.fm", np.ToString(), ToolTipIcon.None);
            }
            catch (Exception ex)
            {
                Log.Write("Love failed: " + ex.Message);
                ShowBalloon("Couldn't love this song", ex.Message, ToolTipIcon.Warning);
            }
        }

        async Task CheckForUpdateAsync(bool manual)
        {
            if (!manual && !_settings.CheckForUpdates) return;
            try
            {
                var release = await UpdateChecker.GetNewerReleaseAsync();
                if (release == null)
                {
                    if (manual) ShowBalloon("You're up to date", $"{AppInfo.Name} {AppInfo.Version} is the latest version.", ToolTipIcon.Info);
                    return;
                }

                _update = release;
                _updateItem.Text = $"⬆ Update available: {release.Tag}";
                _updateItem.Visible = true;
                if (manual || _settings.UpdateNotifiedFor != release.Tag)
                {
                    Log.Write("Update available: " + release.Tag);
                    _settings.UpdateNotifiedFor = release.Tag;
                    SaveSettings();
                    ShowBalloon("Update available", $"{AppInfo.Name} {release.Tag} is out. Click to install it.", ToolTipIcon.Info, release.Url, installsUpdate: true);
                }
            }
            catch (Exception ex)
            {
                Log.Write("Update check failed: " + ex.Message);
                if (manual) ShowBalloon("Couldn't check for updates", ex.Message, ToolTipIcon.Warning);
            }
        }

        void ReportProblem()
        {
            Log.Write("Opened the problem report form");
            AppInfo.OpenUrl(IssueReport.Url(AppInfo.GitHubRepo, AppInfo.Version, IssueReport.SystemDescription(), IssueReport.ReadLog()));
        }

        /// <summary>Asks before installing; No opens the release page instead.</summary>
        async void OfferUpdate()
        {
            var release = _update;
            if (release == null || _installing) return;
            string reason = string.IsNullOrEmpty(release.DownloadUrl) ? "this release has no checked download for Windows" : Updater.CannotInstallReason();
            if (reason != null)
            {
                if (MessageBox.Show($"{AppInfo.Name} {release.Tag} is out, but the app can't update itself because {reason}.\n\nOpen the release page to download it?",
                        AppInfo.Name, MessageBoxButtons.YesNo, MessageBoxIcon.Information) == DialogResult.Yes)
                    AppInfo.OpenUrl(release.Url);
                return;
            }

            var answer = MessageBox.Show(
                $"Update to {AppInfo.Name} {release.Tag}?\n\nThe app downloads the new version, checks it, and restarts. Your settings and Last.fm login are kept.\n\n" +
                "Yes: install and restart\nNo: open the release notes instead",
                AppInfo.Name, MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
            if (answer == DialogResult.No) AppInfo.OpenUrl(release.Url);
            if (answer != DialogResult.Yes) return;

            _installing = true;
            _updateItem.Text = $"Installing {release.Tag}...";
            _updateItem.Enabled = false;
            try
            {
                await Updater.InstallAsync(release);
                ExitThread();
            }
            catch (Exception ex)
            {
                _installing = false;
                _updateItem.Text = $"⬆ Update available: {release.Tag}";
                _updateItem.Enabled = true;
                Log.Write($"Update to {release.Tag} failed: {ex.Message}");
                ShowBalloon("Couldn't install the update", ex.Message + ". Click to download it from the release page.", ToolTipIcon.Warning, release.Url);
            }
        }

        void ShowAbout()
        {
            string text = $"{AppInfo.Name} {AppInfo.Version}\n\nScrobbles the Apple Music app for Windows to Last.fm.\nNot affiliated with Apple or Last.fm.";
            if (AppInfo.RepoUrl.Length == 0)
            {
                MessageBox.Show(text, AppInfo.Name, MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            var answer = MessageBox.Show(text + "\n\nOpen the project page (and check for updates)?", AppInfo.Name,
                MessageBoxButtons.YesNo, MessageBoxIcon.Information);
            if (answer == DialogResult.Yes)
            {
                AppInfo.OpenUrl(AppInfo.RepoUrl);
                _ = CheckForUpdateAsync(manual: true);
            }
        }

        void TogglePause()
        {
            _settings.Paused = !_settings.Paused;
            _pauseItem.Checked = _settings.Paused;
            _tray.Icon = _settings.Paused ? _iconPaused : _iconActive;
            SaveSettings();
            Log.Write(_settings.Paused ? "Scrobbling paused" : "Scrobbling resumed");
            UpdateUi();
        }

        void ToggleStartup()
        {
            Startup.Set(!Startup.IsEnabled);
            _startupItem.Checked = Startup.IsEnabled;
        }

        void ToggleDiscord()
        {
            _settings.ShowOnDiscord = !_settings.ShowOnDiscord;
            _discordItem.Checked = _settings.ShowOnDiscord;
            SaveSettings();
            Log.Write(_settings.ShowOnDiscord ? "Discord status turned on" : "Discord status turned off");
        }

        void ToggleUpdateChecks()
        {
            _settings.CheckForUpdates = !_settings.CheckForUpdates;
            _checkUpdatesItem.Checked = _settings.CheckForUpdates;
            SaveSettings();
        }

        void Reconnect()
        {
            using (var setup = new SetupForm(_settings))
            {
                if (setup.ShowDialog() != DialogResult.OK) return;
            }
            _authWarningShown = false;
            _startupItem.Checked = Startup.IsEnabled;
            _scrobbler.RetrySoon();
            Log.Write("Now scrobbling as " + _settings.Username);
        }

        void OnAuthProblem()
        {
            if (_authWarningShown) return;
            _authWarningShown = true;
            ShowBalloon("Last.fm needs you to reconnect",
                "Right-click the tray icon and choose Options > \"Switch Last.fm account...\". Your scrobbles are saved until then.",
                ToolTipIcon.Warning);
        }

        void OpenLog()
        {
            try { Process.Start("notepad.exe", "\"" + Log.FilePath + "\""); }
            catch (Exception ex) { Log.Write("Could not open the log: " + ex.Message); }
        }

        void SaveSettings()
        {
            try { _settings.Save(); }
            catch (Exception ex) { Log.Write("Could not save settings: " + ex.Message); }
        }

        protected override void ExitThreadCore()
        {
            _timer.Stop();
            _updateTimer.Stop();
            _discord.Dispose();
            _tray.Visible = false;
            _tray.Dispose();
            Log.Write("Stopped");
            base.ExitThreadCore();
        }
    }
}
