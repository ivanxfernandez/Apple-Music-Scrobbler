using System;
using System.Diagnostics;
using System.Drawing;
using System.Reflection;
using System.Windows.Forms;

namespace AppleMusicScrobbler
{
    /// <summary>The tray icon and its menu; polls Apple Music once a second.</summary>
    public class TrayApp : ApplicationContext
    {
        readonly Settings _settings;
        readonly LastFmClient _api;
        readonly MediaReader _reader = new MediaReader();
        readonly Scrobbler _scrobbler;

        readonly NotifyIcon _tray;
        readonly Timer _timer;
        readonly Icon _iconActive, _iconPaused;
        readonly ToolStripMenuItem _nowItem, _lastItem, _loveItem, _pauseItem, _startupItem;

        bool _busy;
        bool _authWarningShown;
        string _lastError;

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
            _loveItem = new ToolStripMenuItem("♥ Love this song on Last.fm", null, async (s, e) => await LoveCurrentAsync());
            _pauseItem = new ToolStripMenuItem("Pause scrobbling", null, (s, e) => TogglePause()) { Checked = settings.Paused };
            _startupItem = new ToolStripMenuItem("Start with Windows", null, (s, e) => ToggleStartup()) { Checked = Startup.IsEnabled };

            var menu = new ContextMenuStrip();
            menu.Items.AddRange(new ToolStripItem[]
            {
                _nowItem,
                _lastItem,
                new ToolStripSeparator(),
                _loveItem,
                _pauseItem,
                new ToolStripSeparator(),
                new ToolStripMenuItem("Open my Last.fm profile", null, (s, e) => AppInfo.OpenUrl("https://www.last.fm/user/" + Uri.EscapeDataString(_settings.Username ?? ""))),
                new ToolStripMenuItem("Switch Last.fm account...", null, (s, e) => Reconnect()),
                _startupItem,
                new ToolStripMenuItem("Open log", null, (s, e) => OpenLog()),
                new ToolStripSeparator(),
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
                if (e.Button == MouseButtons.Left)
                    typeof(NotifyIcon).GetMethod("ShowContextMenu", BindingFlags.Instance | BindingFlags.NonPublic)?.Invoke(_tray, null);
            };

            _timer = new Timer { Interval = 1000 };
            _timer.Tick += OnTick;
            _timer.Start();

            Log.Write(Program.DryRun
                ? $"Started {AppInfo.Version} (dry run: nothing is sent to Last.fm)"
                : $"Started {AppInfo.Version}, scrobbling as {_settings.Username}");

            if (justConnected)
                _tray.ShowBalloonTip(8000, "Connected to Last.fm",
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
            SetText(_lastItem, _scrobbler.LastScrobbled != null ? MenuText("Last scrobbled: " + _scrobbler.LastScrobbled) : "Nothing scrobbled yet");
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

        async System.Threading.Tasks.Task LoveCurrentAsync()
        {
            var np = _scrobbler.Current;
            if (np == null || !np.IsValid) return;
            try
            {
                await _api.LoveAsync(np.Artist, np.Title);
                Log.Write("Loved: " + np);
                _tray.ShowBalloonTip(3000, "♥ Loved on Last.fm", np.ToString(), ToolTipIcon.None);
            }
            catch (Exception ex)
            {
                Log.Write("Love failed: " + ex.Message);
                _tray.ShowBalloonTip(5000, "Couldn't love this song", ex.Message, ToolTipIcon.Warning);
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
            _tray.ShowBalloonTip(15000, "Last.fm needs you to reconnect",
                "Right-click the tray icon and choose \"Switch Last.fm account...\". Your scrobbles are saved until then.",
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
            _tray.Visible = false;
            _tray.Dispose();
            Log.Write("Stopped");
            base.ExitThreadCore();
        }
    }
}
