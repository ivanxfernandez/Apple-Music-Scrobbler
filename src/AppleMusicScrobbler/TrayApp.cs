using System;
using System.Diagnostics;
using System.Drawing;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows.Forms;

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

        readonly NotifyIcon _tray;
        readonly Timer _timer;
        readonly Timer _updateTimer;
        readonly Icon _iconActive, _iconPaused;
        readonly ToolStripMenuItem _nowItem, _lastItem, _updateItem, _loveItem, _pauseItem;
        readonly ToolStripMenuItem _startupItem, _checkUpdatesItem;

        bool _busy;
        bool _authWarningShown;
        string _lastError;
        string _balloonUrl;
        ReleaseInfo _update;

        public TrayApp(Settings settings, bool justConnected)
        {
            _settings = settings;
            _api = new LastFmClient(settings);
            _scrobbler = new Scrobbler(settings, _api, Program.DryRun);
            _scrobbler.AuthProblem += OnAuthProblem;

            int iconSize = SystemInformation.SmallIconSize.Width;
            _iconActive = IconFactory.CreateIcon(IconFactory.Red, iconSize);
            _iconPaused = IconFactory.CreateIcon(IconFactory.Grey, iconSize);

            _nowItem = new ToolStripMenuItem("Nothing playing") { Enabled = false };
            _lastItem = new ToolStripMenuItem("Nothing scrobbled yet") { Enabled = false };
            _updateItem = new ToolStripMenuItem("Update available", null, (s, e) => AppInfo.OpenUrl(_update?.Url)) { Visible = false };
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
            options.DropDownItems.AddRange(new ToolStripItem[]
            {
                _startupItem,
                cleanItem,
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
                new ToolStripSeparator(),
                _updateItem,
                _loveItem,
                _pauseItem,
                new ToolStripMenuItem("Open my Last.fm profile", null, (s, e) => AppInfo.OpenUrl("https://www.last.fm/user/" + Uri.EscapeDataString(_settings.Username ?? ""))),
                options,
                new ToolStripSeparator(),
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
            _tray.BalloonTipClicked += (s, e) => { if (_balloonUrl != null) AppInfo.OpenUrl(_balloonUrl); };
            _tray.BalloonTipClosed += (s, e) => _balloonUrl = null;

            _timer = new Timer { Interval = 1000 };
            _timer.Tick += OnTick;
            _timer.Start();

            // First update check a minute after starting, then daily.
            _updateTimer = new Timer { Interval = 60 * 1000 };
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
            _loveItem.Enabled = np != null && np.IsValid && !Program.DryRun;

            string tip = (_settings.Paused ? "Scrobbling paused\n" : "") + playing;
            if (_scrobbler.Pending > 0) tip += $"\n{_scrobbler.Pending} waiting to send";
            if (tip.Length > 63) tip = tip.Substring(0, 62) + "…"; // Windows limit
            if (_tray.Text != tip) _tray.Text = tip;
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

        void ShowBalloon(string title, string text, ToolTipIcon icon, string clickUrl = null)
        {
            _balloonUrl = clickUrl;
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
                    ShowBalloon("Update available", $"{AppInfo.Name} {release.Tag} is out. Click to download it.", ToolTipIcon.Info, release.Url);
                }
            }
            catch (Exception ex)
            {
                Log.Write("Update check failed: " + ex.Message);
                if (manual) ShowBalloon("Couldn't check for updates", ex.Message, ToolTipIcon.Warning);
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
            _tray.Visible = false;
            _tray.Dispose();
            Log.Write("Stopped");
            base.ExitThreadCore();
        }
    }
}
