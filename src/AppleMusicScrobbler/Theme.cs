using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

namespace AppleMusicScrobbler
{
    /// <summary>
    /// Light or dark, following Windows' "Choose your app mode" setting. WinForms has no dark mode of
    /// its own, so the tray menu gets a dark renderer and the setup window dark colors and a dark title
    /// bar. Message boxes are drawn by Windows and stay light.
    /// </summary>
    static class Theme
    {
        /// <summary>Read each time, so switching the Windows setting applies the next time a menu or window opens.</summary>
        public static bool IsDark
        {
            get
            {
                try
                {
                    using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"))
                        return key?.GetValue("AppsUseLightTheme") is int light && light == 0;
                }
                catch
                {
                    return false;
                }
            }
        }

        // Windows 11 dark palette.
        public static readonly Color DarkBackground = Color.FromArgb(32, 32, 32);
        public static readonly Color DarkMenuBackground = Color.FromArgb(44, 44, 44);
        public static readonly Color DarkHover = Color.FromArgb(61, 61, 61);
        public static readonly Color DarkField = Color.FromArgb(45, 45, 45);
        public static readonly Color DarkBorder = Color.FromArgb(80, 80, 80);
        public static readonly Color DarkText = Color.FromArgb(242, 242, 242);
        public static readonly Color DarkSecondaryText = Color.FromArgb(160, 160, 160);
        public static readonly Color DarkLink = Color.FromArgb(76, 194, 255);
        public static readonly Color DarkError = Color.FromArgb(255, 153, 164);

        public static Color SecondaryText => IsDark ? DarkSecondaryText : SystemColors.GrayText;
        public static Color ErrorText => IsDark ? DarkError : Color.Firebrick;

        /// <summary>Use for all menus (they render through ToolStripManager). Call when a menu opens.</summary>
        public static void ApplyToMenus()
        {
            bool dark = IsDark;
            if (dark && !(ToolStripManager.Renderer is DarkMenuRenderer)) ToolStripManager.Renderer = new DarkMenuRenderer();
            else if (!dark && ToolStripManager.Renderer is DarkMenuRenderer) ToolStripManager.Renderer = new ToolStripProfessionalRenderer();
        }

        /// <summary>Dark colors for a window and its controls (call after creating them). Does nothing in light mode.</summary>
        public static void Apply(Control root)
        {
            if (!IsDark) return;
            root.BackColor = DarkBackground;
            root.ForeColor = DarkText;
            ApplyToChildren(root);
        }

        static void ApplyToChildren(Control parent)
        {
            foreach (Control c in parent.Controls)
            {
                switch (c)
                {
                    case LinkLabel link:
                        link.LinkColor = DarkLink;
                        link.ActiveLinkColor = DarkLink;
                        link.VisitedLinkColor = DarkLink;
                        break;
                    case Label label:
                        if (label.ForeColor == SystemColors.ControlText) label.ForeColor = DarkText;
                        break;
                    case TextBox box:
                        box.BackColor = DarkField;
                        box.ForeColor = DarkText;
                        box.BorderStyle = BorderStyle.FixedSingle;
                        break;
                    case Button button:
                        button.FlatStyle = FlatStyle.Flat;
                        button.BackColor = DarkField;
                        button.ForeColor = DarkText;
                        button.FlatAppearance.BorderColor = DarkBorder;
                        button.FlatAppearance.MouseOverBackColor = DarkHover;
                        button.UseVisualStyleBackColor = false;
                        break;
                    case CheckBox check:
                        check.FlatStyle = FlatStyle.Flat;
                        check.ForeColor = DarkText;
                        check.FlatAppearance.BorderColor = DarkSecondaryText;
                        check.FlatAppearance.CheckedBackColor = DarkField;
                        break;
                }
                ApplyToChildren(c);
            }
        }

        [DllImport("dwmapi.dll")]
        static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

        /// <summary>Dark title bar (Windows 10 2004+ / 11); ignored where unsupported.</summary>
        public static void UseDarkTitleBar(IntPtr handle)
        {
            if (!IsDark) return;
            try
            {
                int on = 1;
                if (DwmSetWindowAttribute(handle, 20, ref on, sizeof(int)) != 0) // DWMWA_USE_IMMERSIVE_DARK_MODE
                    DwmSetWindowAttribute(handle, 19, ref on, sizeof(int));      // the same, before Windows 10 20H1
            }
            catch
            {
                // dwmapi missing: keep the light title bar.
            }
        }

        sealed class DarkColors : ProfessionalColorTable
        {
            public override Color ToolStripDropDownBackground => DarkMenuBackground;
            public override Color ImageMarginGradientBegin => DarkMenuBackground;
            public override Color ImageMarginGradientMiddle => DarkMenuBackground;
            public override Color ImageMarginGradientEnd => DarkMenuBackground;
            public override Color MenuBorder => DarkBorder;
            public override Color MenuItemBorder => DarkHover;
            public override Color MenuItemSelected => DarkHover;
            public override Color MenuItemSelectedGradientBegin => DarkHover;
            public override Color MenuItemSelectedGradientEnd => DarkHover;
            public override Color MenuItemPressedGradientBegin => DarkHover;
            public override Color MenuItemPressedGradientEnd => DarkHover;
            public override Color SeparatorDark => DarkBorder;
            public override Color SeparatorLight => DarkMenuBackground;
            public override Color CheckBackground => DarkMenuBackground;
            public override Color CheckSelectedBackground => DarkHover;
            public override Color CheckPressedBackground => DarkHover;
            public override Color ButtonSelectedBorder => DarkHover;
        }

        sealed class DarkMenuRenderer : ToolStripProfessionalRenderer
        {
            public DarkMenuRenderer() : base(new DarkColors()) { RoundedEdges = false; }

            protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
            {
                e.TextColor = e.Item.Enabled ? DarkText : DarkSecondaryText;
                base.OnRenderItemText(e);
            }

            protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e)
            {
                e.ArrowColor = DarkText;
                base.OnRenderArrow(e);
            }

            // The standard check mark is a black glyph; draw a light one instead.
            protected override void OnRenderItemCheck(ToolStripItemImageRenderEventArgs e)
            {
                var r = e.ImageRectangle;
                if (r.Width <= 0) return;
                using (var pen = new Pen(DarkText, Math.Max(1.5f, r.Height / 9f)))
                {
                    e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
                    e.Graphics.DrawLines(pen, new[]
                    {
                        new PointF(r.Left + r.Width * 0.22f, r.Top + r.Height * 0.52f),
                        new PointF(r.Left + r.Width * 0.42f, r.Top + r.Height * 0.72f),
                        new PointF(r.Left + r.Width * 0.78f, r.Top + r.Height * 0.30f),
                    });
                }
            }
        }
    }
}
