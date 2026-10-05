using System;
using System.Diagnostics;
using System.Drawing;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows.Forms;
using AppleMusicScrobbler.Discord;
using static AppleMusicScrobbler.Localization;

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
        readonly ToolStripMenuItem _nowItem, _lastItem, _recentItem, _updateItem, _loveItem, _ignoreItem, _ignoredListItem, _pauseItem;
        readonly ToolStripMenuItem _startupItem, _checkUpdatesItem, _discordItem, _loveShortcutItem, _nowPlayingNotificationItem;
        HotKey _loveHotKey;
        /// <summary>Whether songs (artist + title as sent to Last.fm) are loved there; filled in as songs play.</summary>
        readonly System.Collections.Generic.Dictionary<string, bool> _loved = new System.Collections.Generic.Dictionary<string, bool>();
        readonly System.Collections.Generic.HashSet<string> _lovedPending = new System.Collections.Generic.HashSet<string>();

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
            _scrobbler.NowPlayingStarted += ShowNowPlaying;
            _discord = new DiscordPresence(settings);

            int iconSize = SystemInformation.SmallIconSize.Width;
            _iconActive = IconFactory.CreateIcon(IconFactory.Red, iconSize);
            _iconPaused = IconFactory.CreateIcon(IconFactory.Grey, iconSize);

            _nowItem = new ToolStripMenuItem(L("Nothing playing")) { Enabled = false };
            _lastItem = new ToolStripMenuItem(L("Nothing scrobbled yet")) { Enabled = false };
            _recentItem = new ToolStripMenuItem(L("Recent scrobbles"));
            _recentItem.DropDownItems.Add("Nothing scrobbled yet"); // placeholder so the arrow shows; filled when opened
            _recentItem.DropDownOpening += (s, e) => BuildRecentMenu();
            _updateItem = new ToolStripMenuItem(L("Update available"), null, (s, e) => OfferUpdate()) { Visible = false };
            _updateItem.Font = new Font(_updateItem.Font, FontStyle.Bold);
            _loveItem = new ToolStripMenuItem(L("♥ Love this song on Last.fm"), null, async (s, e) => await SetLovedAsync(LovedState() != true))
            {
                ShortcutKeyDisplayString = HotKey.LoveDescription,
            };
            _loveShortcutItem = new ToolStripMenuItem(L("♥ Keyboard shortcut ({0})", HotKey.LoveDescription), null, (s, e) =>
            {
                _settings.LoveShortcut = !_settings.LoveShortcut;
                SaveSettings();
                UpdateLoveShortcut();
            });
            _nowPlayingNotificationItem = new ToolStripMenuItem(L("Show a notification when a song starts"), null, (s, e) =>
            {
                _settings.NowPlayingNotification = !_settings.NowPlayingNotification;
                _nowPlayingNotificationItem.Checked = _settings.NowPlayingNotification;
                SaveSettings();
            }) { Checked = settings.NowPlayingNotification };
            _ignoreItem = new ToolStripMenuItem(L("Don't scrobble this artist"), null, (s, e) => ToggleIgnoreCurrent());
            _ignoredListItem = new ToolStripMenuItem(L("Ignored artists"));
            _ignoredListItem.DropDownItems.Add("No ignored artists"); // placeholder so the arrow shows; filled when opened
            _ignoredListItem.DropDownOpening += (s, e) => BuildIgnoredMenu();
            _pauseItem = new ToolStripMenuItem(L("Pause scrobbling"), null, (s, e) => TogglePause()) { Checked = settings.Paused };

            _startupItem = new ToolStripMenuItem(L("Start with Windows"), null, (s, e) => ToggleStartup()) { Checked = Startup.IsEnabled };
            _checkUpdatesItem = new ToolStripMenuItem(L("Check for updates automatically"), null, (s, e) => ToggleUpdateChecks())
            {
                Checked = settings.CheckForUpdates,
                Visible = AppInfo.GitHubRepo.Length > 0,
            };
            var options = new ToolStripMenuItem(L("Options"));
            var cleanItem = new ToolStripMenuItem(L("Clean up titles (remove “Remaster”, “- Single”…)"))
            {
                Checked = settings.CleanTitles,
                ToolTipText = L("“Song [2022 Remaster]” is scrobbled as “Song”, “Album (Deluxe Edition)” as “Album”"),
            };
            cleanItem.Click += (s, e) =>
            {
                _settings.CleanTitles = !_settings.CleanTitles;
                cleanItem.Checked = _settings.CleanTitles;
                SaveSettings();
            };
            var mainArtistItem = new ToolStripMenuItem(L("Scrobble only the main artist of collaborations"))
            {
                Checked = settings.MainArtistOnly,
                ToolTipText = L("“Joji & BENEE” is scrobbled as “Joji”. Bands like “Simon & Garfunkel” are left alone (Last.fm's listener counts tell them apart)."),
            };
            mainArtistItem.Click += (s, e) =>
            {
                _settings.MainArtistOnly = !_settings.MainArtistOnly;
                mainArtistItem.Checked = _settings.MainArtistOnly;
                SaveSettings();
                Log.Write(_settings.MainArtistOnly ? "Scrobbling only the main artist of collaborations" : "Scrobbling full artist credits");
            };
            _discordItem = new ToolStripMenuItem(L("Show “Listening to” on Discord"), null, (s, e) => ToggleDiscord())
            {
                Checked = settings.ShowOnDiscord,
                Visible = DiscordPresence.Available,
            };
            options.DropDownItems.AddRange(new ToolStripItem[]
            {
                _startupItem,
                _discordItem,
                _nowPlayingNotificationItem,
                _loveShortcutItem,
                cleanItem,
                mainArtistItem,
                _checkUpdatesItem,
                _ignoredListItem,
                new ToolStripSeparator(),
                new ToolStripMenuItem(L("Switch Last.fm account..."), null, (s, e) => Reconnect()),
                new ToolStripMenuItem(L("Open log"), null, (s, e) => OpenLog()),
            });

            Theme.ApplyToMenus();
            var menu = new ContextMenuStrip();
            menu.Opening += (s, e) => Theme.ApplyToMenus(); // follows a theme switch without restarting
            menu.Items.AddRange(new ToolStripItem[]
            {
                _nowItem,
                _lastItem,
                _recentItem,
                new ToolStripSeparator(),
                _updateItem,
                _loveItem,
                _ignoreItem,
                _pauseItem,
                new ToolStripMenuItem(L("Open my Last.fm profile"), null, (s, e) => AppInfo.OpenUrl("https://www.last.fm/user/" + Uri.EscapeDataString(_settings.Username ?? ""))),
                options,
                new ToolStripSeparator(),
                new ToolStripMenuItem(L("Report a problem..."), null, (s, e) => ReportProblem()),
                new ToolStripMenuItem(L("About {0}", AppInfo.Name), null, (s, e) => ShowAbout()),
                new ToolStripMenuItem(L("Quit"), null, (s, e) => ExitThread()),
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

            UpdateLoveShortcut();

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
                ShowBalloon(L("Updated to {0}", AppInfo.Version), L("{0} is up to date. Click to see what's new.", AppInfo.Name), ToolTipIcon.Info,
                    AppInfo.RepoUrl.Length > 0 ? $"{AppInfo.RepoUrl}/releases/tag/v{AppInfo.Version}" : null);
            }
            if (_settings.LastRunVersion != AppInfo.Version)
            {
                _settings.LastRunVersion = AppInfo.Version;
                SaveSettings();
            }

            if (justConnected)
                ShowBalloon(L("Connected to Last.fm"),
                    L("Scrobbling Apple Music as {0}. I'll be here in the tray.", _settings.Username), ToolTipIcon.Info);
        }

        async void OnTick(object sender, EventArgs e)
        {
            if (_busy) return;
            _busy = true;
            try
            {
                var np = await _reader.ReadAsync();
                _scrobbler.Update(np);
                // Same (cleaned) track info as Last.fm gets; nothing for ignored artists.
                _discord.Update(_scrobbler.CurrentIsIgnored ? null : _scrobbler.Current);
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
            bool ignored = _scrobbler.CurrentIsIgnored;
            string playing = L("Nothing playing");
            if (np != null && np.IsValid)
            {
                playing = np.ToString();
                if (!np.IsPlaying) playing = L("{0} (paused)", playing);
                if (ignored) playing = L("{0} (not scrobbled)", playing);
            }

            SetText(_nowItem, MenuText(playing));
            SetText(_lastItem, string.IsNullOrEmpty(_scrobbler.LastScrobbled) ? L("Nothing scrobbled yet") : MenuText(L("Last scrobbled: {0}", _scrobbler.LastScrobbled)));
            SetText(_recentItem, _scrobbler.Pending > 0 ? L("Recent scrobbles ({0} waiting)", _scrobbler.Pending) : L("Recent scrobbles"));
            _loveItem.Enabled = np != null && np.IsValid && !Program.DryRun;
            _loveItem.Checked = LovedState() == true;
            _loveItem.ShortcutKeyDisplayString = _loveHotKey != null ? HotKey.LoveDescription : null;
            _ignoreItem.Enabled = np != null && np.IsValid;
            SetText(_ignoreItem, np != null && np.IsValid
                ? MenuText(ignored ? L("Scrobble {0} again", np.Artist) : L("Don't scrobble {0}", np.Artist))
                : L("Don't scrobble this artist"));
            SetText(_discordItem, _settings.ShowOnDiscord && !_discord.IsConnected
                ? L("Show “Listening to” on Discord (waiting for Discord)") : L("Show “Listening to” on Discord"));

            string tip = (_settings.Paused ? L("Scrobbling paused") + "\n" : "") + playing;
            if (_scrobbler.Pending > 0) tip += "\n" + L("{0} waiting to send", _scrobbler.Pending);
            if (tip.Length > 63) tip = tip.Substring(0, 62) + "…"; // Windows limit
            if (_tray.Text != tip) _tray.Text = tip;
        }

        /// <summary>Latest scrobbles (click one to open it on Last.fm), anything waiting to be sent, and Send now.</summary>
        void BuildRecentMenu()
        {
            var items = _recentItem.DropDownItems;
            items.Clear();
            var recent = _scrobbler.Recent;
            if (recent.Count == 0) items.Add(new ToolStripMenuItem(L("Nothing scrobbled yet")) { Enabled = false });
            foreach (var r in recent)
            {
                string url = r.Url;
                items.Add(new ToolStripMenuItem(MenuText($"{RecentScrobbles.Time(r, DateTime.Now)}   {r.Artist} - {r.Track}"), null,
                    (s, e) => AppInfo.OpenUrl(url)) { ToolTipText = L("Open on Last.fm") });
            }

            var pending = _scrobbler.PendingScrobbles;
            if (pending.Count > 0)
            {
                items.Add(new ToolStripSeparator());
                items.Add(new ToolStripMenuItem(pending.Count == 1 ? L("1 waiting to send") : L("{0} waiting to send", pending.Count)) { Enabled = false });
                for (int i = pending.Count - 1; i >= Math.Max(0, pending.Count - 5); i--)
                    items.Add(new ToolStripMenuItem(MenuText($"    {pending[i].Artist} - {pending[i].Track}")) { Enabled = false });
                items.Add(new ToolStripMenuItem(L("Send now"), null, (s, e) =>
                {
                    Log.Write($"Sending {_scrobbler.Pending} waiting scrobble(s) now");
                    _scrobbler.RetrySoon();
                }) { Enabled = !Program.DryRun });
            }

            items.Add(new ToolStripSeparator());
            items.Add(new ToolStripMenuItem(L("Open my Last.fm library"), null,
                (s, e) => AppInfo.OpenUrl("https://www.last.fm/user/" + Uri.EscapeDataString(_settings.Username ?? "") + "/library")));
        }

        void ToggleIgnoreCurrent()
        {
            var np = _scrobbler.Current;
            if (np == null || !np.IsValid) return;
            if (_scrobbler.CurrentIsIgnored)
            {
                _settings.IgnoredArtists = _settings.IgnoredArtists.Where(a => !IgnoreList.IsIgnored(np.Artist, new[] { a })).ToList();
                Log.Write($"Scrobbling {np.Artist} again");
            }
            else
            {
                _settings.IgnoredArtists = IgnoreList.Adding(np.Artist, _settings.IgnoredArtists);
                Log.Write($"Ignoring {np.Artist}: not scrobbled or shown on Discord");
            }
            SaveSettings();
            UpdateUi();
        }

        /// <summary>Ignored artists; clicking one scrobbles it again.</summary>
        void BuildIgnoredMenu()
        {
            var items = _ignoredListItem.DropDownItems;
            items.Clear();
            var artists = _settings.IgnoredArtists;
            items.Add(new ToolStripMenuItem(artists.Count == 0
                ? L("No ignored artists. Use \"Don't scrobble\" while one plays.")
                : L("Not sent to Last.fm or shown on Discord. Click to undo:")) { Enabled = false });
            foreach (string artist in artists.ToList())
            {
                string name = artist;
                items.Add(new ToolStripMenuItem(MenuText(name), null, (s, e) =>
                {
                    _settings.IgnoredArtists = IgnoreList.Removing(name, _settings.IgnoredArtists);
                    SaveSettings();
                    Log.Write($"Scrobbling {name} again");
                    UpdateUi();
                }));
            }
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

        /// <summary>Whether the current song is loved on Last.fm; null while unknown (starts the lookup).</summary>
        bool? LovedState()
        {
            var np = _scrobbler.CurrentAsSent;
            if (np == null || Program.DryRun || string.IsNullOrEmpty(_settings.Username)) return null;
            string key = np.Artist + "\n" + np.Title;
            if (_loved.TryGetValue(key, out bool known)) return known;
            if (_lovedPending.Add(key)) _ = LookUpLovedAsync(np, key);
            return null;
        }

        async Task LookUpLovedAsync(NowPlaying np, string key)
        {
            try
            {
                bool isLoved = await _api.IsLovedAsync(np.Artist, np.Title, _settings.Username);
                if (_loved.Count > 500) _loved.Clear();
                _loved[key] = isLoved;
            }
            catch
            {
                // Unknown: the item just shows without a check mark.
            }
            _lovedPending.Remove(key);
            UpdateUi();
        }

        /// <summary>The menu item loves the song, or un-loves it if it's already loved (shown checked).</summary>
        async Task SetLovedAsync(bool love)
        {
            var np = _scrobbler.CurrentAsSent;
            if (np == null) return;
            string key = np.Artist + "\n" + np.Title;
            try
            {
                if (love) await _api.LoveAsync(np.Artist, np.Title);
                else await _api.UnloveAsync(np.Artist, np.Title);
                _loved[key] = love;
                Log.Write((love ? "Loved: " : "Unloved: ") + np);
                ShowBalloon(love ? L("♥ Loved on Last.fm") : L("Removed from your loved tracks"), np.ToString(), ToolTipIcon.None);
                UpdateUi();
            }
            catch (Exception ex)
            {
                Log.Write((love ? "Love" : "Unlove") + " failed: " + ex.Message);
                ShowBalloon(love ? L("Couldn't love this song") : L("Couldn't remove the love"), ex.Message, ToolTipIcon.Warning);
            }
        }

        /// <summary>The keyboard shortcut only loves; it never takes a love back.</summary>
        void LoveFromShortcut()
        {
            var np = _scrobbler.CurrentAsSent;
            if (np == null || Program.DryRun)
                ShowBalloon(L("Nothing playing"), L("Play a song in Apple Music, then press {0} to love it.", HotKey.LoveDescription), ToolTipIcon.Info);
            else if (LovedState() == true)
                ShowBalloon(L("Already loved"), np.ToString(), ToolTipIcon.None);
            else
                _ = SetLovedAsync(true);
        }

        void UpdateLoveShortcut()
        {
            _loveHotKey?.Dispose();
            _loveHotKey = _settings.LoveShortcut ? HotKey.Love(LoveFromShortcut) : null;
            if (_settings.LoveShortcut && _loveHotKey == null)
                Log.Write($"The love shortcut {HotKey.LoveDescription} is used by another app; turn it off in Options or quit that app");
            _loveShortcutItem.Checked = _settings.LoveShortcut;
            UpdateUi();
        }

        /// <summary>The optional "now playing" notification (text only: Windows notifications from a tray app can't show album art).</summary>
        void ShowNowPlaying(NowPlaying np)
        {
            if (!_settings.NowPlayingNotification) return;
            ShowBalloon(np.Title, np.Album.Length > 0 ? $"{np.Artist} — {np.Album}" : np.Artist, ToolTipIcon.None);
        }

        async Task CheckForUpdateAsync(bool manual)
        {
            if (!manual && !_settings.CheckForUpdates) return;
            try
            {
                var release = await UpdateChecker.GetNewerReleaseAsync();
                if (release == null)
                {
                    if (manual) ShowBalloon(L("You're up to date"), L("{0} {1} is the latest version.", AppInfo.Name, AppInfo.Version), ToolTipIcon.Info);
                    return;
                }

                _update = release;
                _updateItem.Text = L("⬆ Update available: {0}", release.Tag);
                _updateItem.Visible = true;
                if (manual || _settings.UpdateNotifiedFor != release.Tag)
                {
                    Log.Write("Update available: " + release.Tag);
                    _settings.UpdateNotifiedFor = release.Tag;
                    SaveSettings();
                    ShowBalloon(L("Update available"), L("{0} {1} is out. Click to install it.", AppInfo.Name, release.Tag), ToolTipIcon.Info, release.Url, installsUpdate: true);
                }
            }
            catch (Exception ex)
            {
                Log.Write("Update check failed: " + ex.Message);
                if (manual) ShowBalloon(L("Couldn't check for updates"), ex.Message, ToolTipIcon.Warning);
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
            string reason = string.IsNullOrEmpty(release.DownloadUrl) ? L("this release has no checked download for Windows") : Updater.CannotInstallReason();
            if (reason != null)
            {
                if (MessageBox.Show(L("{0} {1} is out, but the app can't update itself because {2}.\n\nOpen the release page to download it?", AppInfo.Name, release.Tag, reason),
                        AppInfo.Name, MessageBoxButtons.YesNo, MessageBoxIcon.Information) == DialogResult.Yes)
                    AppInfo.OpenUrl(release.Url);
                return;
            }

            var answer = MessageBox.Show(
                L("Update to {0} {1}?\n\nThe app downloads the new version, checks it, and restarts. Your settings and Last.fm login are kept.\n\nYes: install and restart\nNo: open the release notes instead", AppInfo.Name, release.Tag),
                AppInfo.Name, MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
            if (answer == DialogResult.No) AppInfo.OpenUrl(release.Url);
            if (answer != DialogResult.Yes) return;

            _installing = true;
            _updateItem.Text = L("Installing {0}...", release.Tag);
            _updateItem.Enabled = false;
            try
            {
                await Updater.InstallAsync(release);
                ExitThread();
            }
            catch (Exception ex)
            {
                _installing = false;
                _updateItem.Text = L("⬆ Update available: {0}", release.Tag);
                _updateItem.Enabled = true;
                Log.Write($"Update to {release.Tag} failed: {ex.Message}");
                ShowBalloon(L("Couldn't install the update"), L("{0}. Click to download it from the release page.", ex.Message), ToolTipIcon.Warning, release.Url);
            }
        }

        void ShowAbout()
        {
            string text = L("{0} {1}\n\nScrobbles the Apple Music app for Windows to Last.fm.\nNot affiliated with Apple or Last.fm.", AppInfo.Name, AppInfo.Version);
            if (AppInfo.RepoUrl.Length == 0)
            {
                MessageBox.Show(text, AppInfo.Name, MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            var answer = MessageBox.Show(text + L("\n\nOpen the project page (and check for updates)?"), AppInfo.Name,
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
            ShowBalloon(L("Last.fm needs you to reconnect"),
                L("Right-click the tray icon and choose Options > \"Switch Last.fm account...\". Your scrobbles are saved until then."),
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
            _loveHotKey?.Dispose();
            _updateTimer.Stop();
            _discord.Dispose();
            _tray.Visible = false;
            _tray.Dispose();
            Log.Write("Stopped");
            base.ExitThreadCore();
        }
    }
}
