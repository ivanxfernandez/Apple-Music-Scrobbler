using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace AppleMusicScrobbler
{
    /// <summary>
    /// A system-wide keyboard shortcut (RegisterHotKey), used for Ctrl+Shift+Alt+L: love the current
    /// song from any app. Shift is included because Ctrl+Alt+letter is AltGr+letter on many keyboard
    /// layouts (Spanish, Polish…), which people type all the time.
    /// </summary>
    sealed class HotKey : NativeWindow, IDisposable
    {
        public const string LoveDescription = "Ctrl+Shift+Alt+L";

        const int WM_HOTKEY = 0x0312;
        const uint MOD_ALT = 0x1, MOD_CONTROL = 0x2, MOD_SHIFT = 0x4, MOD_NOREPEAT = 0x4000;
        const int Id = 1;

        [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint key);
        [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        readonly Action _action;
        bool _registered;

        HotKey(Action action)
        {
            _action = action;
            CreateHandle(new CreateParams()); // an invisible window to receive WM_HOTKEY
        }

        /// <summary>Ctrl+Shift+Alt+L, or null if another app already uses it.</summary>
        public static HotKey Love(Action action)
        {
            var hotKey = new HotKey(action);
            hotKey._registered = RegisterHotKey(hotKey.Handle, Id, MOD_CONTROL | MOD_SHIFT | MOD_ALT | MOD_NOREPEAT, (uint)Keys.L);
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
