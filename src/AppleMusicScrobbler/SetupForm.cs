using System;
using System.Drawing;
using System.Windows.Forms;

namespace AppleMusicScrobbler
{
    /// <summary>
    /// First-run window: (optionally) collects a Last.fm API key, then runs Last.fm's desktop
    /// auth flow: get a token, open the approval page in the browser, poll until approved.
    /// </summary>
    public class SetupForm : Form
    {
        const string CreateApiAccountUrl = "https://www.last.fm/api/account/create";

        readonly Settings _settings;
        readonly LastFmClient _api;
        readonly bool _needsApiKey;

        readonly TextBox _keyBox, _secretBox;
        readonly CheckBox _startupBox;
        readonly Button _connectButton;
        readonly Label _status;
        readonly LinkLabel _reopenLink;
        readonly Timer _poll = new Timer { Interval = 3000 };

        string _token;
        DateTime _tokenIssued;

        public SetupForm(Settings settings)
        {
            _settings = settings;
            _api = new LastFmClient(settings);
            _needsApiKey = string.IsNullOrEmpty(AppInfo.BuiltInApiKey) || !string.IsNullOrEmpty(settings.ApiKey);

            // Sizes are derived from the font height so the window scales with Windows display scaling.
            Font = SystemFonts.MessageBoxFont;
            AutoScaleMode = AutoScaleMode.None;
            int u = Font.Height;
            int width = u * 30;

            Text = AppInfo.Name;
            Icon = IconFactory.CreateIcon(IconFactory.Red, 32);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            AutoSize = true;
            AutoSizeMode = AutoSizeMode.GrowAndShrink;
            Padding = new Padding(u);

            var layout = new FlowLayoutPanel
            {
                FlowDirection = FlowDirection.TopDown,
                WrapContents = false,
                AutoSize = true,
                AutoSizeMode = AutoSizeMode.GrowAndShrink,
                Dock = DockStyle.Fill,
            };
            Controls.Add(layout);

            Label Paragraph(string text, int spaceAfter = 0, Font font = null, Color? color = null)
            {
                var label = new Label
                {
                    Text = text,
                    AutoSize = true,
                    MaximumSize = new Size(width, 0),
                    Margin = new Padding(0, 0, 0, spaceAfter),
                    Font = font ?? Font,
                    ForeColor = color ?? SystemColors.ControlText,
                };
                layout.Controls.Add(label);
                return label;
            }

            Paragraph("Connect to Last.fm", u / 2, new Font(Font.FontFamily, Font.Size * 1.5f, FontStyle.Bold));
            Paragraph("This app watches what the Apple Music app is playing and adds it to your Last.fm profile.", u);

            int step = 1;
            if (_needsApiKey)
            {
                Paragraph($"{step++}. Get a free Last.fm API key", u / 4, new Font(Font, FontStyle.Bold));
                Paragraph("Last.fm requires every app to have one. It takes a minute: fill in any application name " +
                          "and description, leave \"Callback URL\" empty, and submit. Then copy the API key and Shared secret here.", u / 4);

                var createLink = new LinkLabel { Text = "Create a Last.fm API account", AutoSize = true, Margin = new Padding(0, 0, 0, u / 2) };
                createLink.LinkClicked += (s, e) => AppInfo.OpenUrl(CreateApiAccountUrl);
                layout.Controls.Add(createLink);

                var grid = new TableLayoutPanel { ColumnCount = 2, AutoSize = true, Margin = new Padding(0, 0, 0, u) };
                grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
                grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
                _keyBox = new TextBox { Width = u * 20, Text = settings.ApiKey };
                _secretBox = new TextBox { Width = u * 20, Text = settings.ApiSecret, UseSystemPasswordChar = true };
                grid.Controls.Add(new Label { Text = "API key", AutoSize = true, Anchor = AnchorStyles.Left }, 0, 0);
                grid.Controls.Add(_keyBox, 1, 0);
                grid.Controls.Add(new Label { Text = "Shared secret", AutoSize = true, Anchor = AnchorStyles.Left }, 0, 1);
                grid.Controls.Add(_secretBox, 1, 1);
                layout.Controls.Add(grid);
            }

            Paragraph($"{step}. Allow access to your account", u / 4, new Font(Font, FontStyle.Bold));
            Paragraph("Click Connect. Last.fm opens in your browser: click \"Yes, allow access\" there and this window finishes by itself.", u / 2);

            _startupBox = new CheckBox
            {
                Text = "Start automatically when I sign in to Windows",
                AutoSize = true,
                Checked = true,
                Margin = new Padding(0, 0, 0, u),
            };
            layout.Controls.Add(_startupBox);

            var buttons = new FlowLayoutPanel
            {
                FlowDirection = FlowDirection.RightToLeft,
                AutoSize = true,
                MinimumSize = new Size(width, 0),
                Margin = new Padding(0),
            };
            var cancel = new Button { Text = "Cancel", DialogResult = DialogResult.Cancel, AutoSize = true, MinimumSize = new Size(u * 5, 0) };
            _connectButton = new Button { Text = "Connect", AutoSize = true, MinimumSize = new Size(u * 5, 0) };
            _connectButton.Click += OnConnectClick;
            buttons.Controls.Add(cancel);
            buttons.Controls.Add(_connectButton);
            layout.Controls.Add(buttons);
            AcceptButton = _connectButton;
            CancelButton = cancel;

            _status = Paragraph("", 0, null, SystemColors.GrayText);
            _status.Margin = new Padding(0, u / 2, 0, 0);
            _reopenLink = new LinkLabel { Text = "Open the Last.fm page again", AutoSize = true, Visible = false };
            _reopenLink.LinkClicked += (s, e) => { if (_token != null) AppInfo.OpenUrl(_api.GetAuthUrl(_token)); };
            layout.Controls.Add(_reopenLink);

            _poll.Tick += OnPollTick;
            FormClosed += (s, e) => _poll.Dispose();
        }

        async void OnConnectClick(object sender, EventArgs e)
        {
            if (_needsApiKey)
            {
                string key = _keyBox.Text.Trim(), secret = _secretBox.Text.Trim();
                if (key.Length == 0 || secret.Length == 0)
                {
                    ShowStatus("Paste both the API key and the Shared secret first.", error: true);
                    return;
                }
                _settings.ApiKey = key;
                _settings.ApiSecret = secret;
            }

            SetBusy(true);
            ShowStatus("Contacting Last.fm...");
            try
            {
                _token = await _api.GetTokenAsync();
                _tokenIssued = DateTime.UtcNow;
                AppInfo.OpenUrl(_api.GetAuthUrl(_token));
                ShowStatus("Waiting for you to click \"Yes, allow access\" on the Last.fm page in your browser...");
                _reopenLink.Visible = true;
                _poll.Start();
            }
            catch (LastFmException ex) when (ex.Code == 10 || ex.Code == 26)
            {
                ShowStatus("Last.fm didn't accept that API key. Check you copied the API key and Shared secret correctly.", error: true);
                SetBusy(false);
            }
            catch (Exception ex)
            {
                ShowStatus("Couldn't reach Last.fm: " + ex.Message, error: true);
                SetBusy(false);
            }
        }

        async void OnPollTick(object sender, EventArgs e)
        {
            _poll.Stop();
            try
            {
                var (key, username) = await _api.GetSessionAsync(_token);
                _settings.SessionKey = key;
                _settings.Username = username;
                _settings.Save();
                Startup.Set(_startupBox.Checked);
                Log.Write("Connected to Last.fm as " + username);
                DialogResult = DialogResult.OK;
                Close();
            }
            catch (LastFmException ex) when (ex.Code == 14) // not approved yet
            {
                if (DateTime.UtcNow - _tokenIssued < TimeSpan.FromMinutes(10)) _poll.Start();
                else Fail("Timed out waiting for approval. Click Connect to try again.");
            }
            catch (LastFmException ex) when (ex.Code == 4 || ex.Code == 15) // token expired/invalid
            {
                Fail("That approval link expired. Click Connect to try again.");
            }
            catch (LastFmException ex) when (ex.Code == 13)
            {
                Fail("Last.fm rejected the Shared secret. Check you copied it correctly.");
            }
            catch (Exception ex)
            {
                if (IsDisposed) return;
                if (DateTime.UtcNow - _tokenIssued < TimeSpan.FromMinutes(10)) _poll.Start(); // network blip: keep trying
                else Fail("Couldn't reach Last.fm: " + ex.Message);
            }
        }

        void Fail(string message)
        {
            if (IsDisposed) return;
            ShowStatus(message, error: true);
            _reopenLink.Visible = false;
            SetBusy(false);
        }

        void ShowStatus(string text, bool error = false)
        {
            _status.Text = text;
            _status.ForeColor = error ? Color.Firebrick : SystemColors.GrayText;
        }

        void SetBusy(bool busy)
        {
            _connectButton.Enabled = !busy;
            if (_keyBox != null) _keyBox.Enabled = _secretBox.Enabled = !busy;
        }
    }
}
