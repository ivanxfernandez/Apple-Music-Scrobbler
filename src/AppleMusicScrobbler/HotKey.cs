using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace AppleMusicScrobbler
{
    /// <summary>
    /// The shortcuts offered for loving the current song from any app (Options > Keyboard shortcut).
    /// None uses Ctrl+Alt+letter: that's AltGr+letter on many keyboard layouts (Spanish, Polish…).
    /// </summary>
    public enum LoveShortcut { WinAltL, AltShiftL, CtrlShiftAltL, Off }

    public static class LoveShortcuts
    {
        public static readonly LoveShortcut Standard = LoveShortcut.WinAltL;

        public static string Describe(LoveShortcut shortcut)
        {
            switch (shortcut)
            {
                case LoveShortcut.WinAltL: return "Win+Alt+L";
                case LoveShortcut.AltShiftL: return "Alt+Shift+L";
                case LoveShortcut.CtrlShiftAltL: return "Ctrl+Shift+Alt+L";
                default: return Localization.L("Off");
            }
        }

        /// <summary>The setting's value (enum name), or the standard shortcut if it's empty or unknown.</summary>
        public static LoveShortcut Parse(string value) =>
            Enum.TryParse(value, out LoveShortcut shortcut) && Enum.IsDefined(typeof(LoveShortcut), shortcut) ? shortcut : Standard;
    }

    /// <summary>A system-wide keyboard shortcut (RegisterHotKey), received by an invisible window.</summary>
    sealed class HotKey : NativeWindow, IDisposable
    {
        const int WM_HOTKEY = 0x0312;
        const uint MOD_ALT = 0x1, MOD_CONTROL = 0x2, MOD_SHIFT = 0x4, MOD_WIN = 0x8, MOD_NOREPEAT = 0x4000;
        const int Id = 1;

        [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint key);
        [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        readonly Action _action;
        bool _registered;

        HotKey(Action action)
        {
            _action = action;
            CreateHandle(new CreateParams());
        }

        /// <summary>The chosen shortcut with L, or null if it's off or another app already uses it.</summary>
        public static HotKey Love(LoveShortcut shortcut, Action action)
        {
            uint modifiers;
            switch (shortcut)
            {
                case LoveShortcut.WinAltL: modifiers = MOD_WIN | MOD_ALT; break;
                case LoveShortcut.AltShiftL: modifiers = MOD_ALT | MOD_SHIFT; break;
                case LoveShortcut.CtrlShiftAltL: modifiers = MOD_CONTROL | MOD_SHIFT | MOD_ALT; break;
                default: return null;
            }
            var hotKey = new HotKey(action);
            hotKey._registered = RegisterHotKey(hotKey.Handle, Id, modifiers | MOD_NOREPEAT, (uint)Keys.L);
            if (hotKey._registered) return hotKey;
            hotKey.Dispose();
            return null;
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == WM_HOTKEY && m.WParam.ToInt32() == Id) _action();
            base.WndProc(ref m);
        }

        public void Dispose()
        {
            if (_registered) UnregisterHotKey(Handle, Id);
            _registered = false;
            DestroyHandle();
        }
    }
}
