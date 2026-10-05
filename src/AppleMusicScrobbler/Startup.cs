using System;
using System.Windows.Forms;
using Microsoft.Win32;

namespace AppleMusicScrobbler
{
    /// <summary>"Start with Windows" via the current user's Run key (no admin rights needed).</summary>
    static class Startup
    {
        const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        const string ValueName = "AppleMusicScrobbler";

        static string Command => "\"" + Application.ExecutablePath + "\"";

        /// <summary>True only if startup points at this exe (moving the exe turns it off until re-enabled).</summary>
        public static bool IsEnabled
        {
            get
            {
                using (var key = Registry.CurrentUser.OpenSubKey(RunKey))
                    return string.Equals(key?.GetValue(ValueName) as string, Command, StringComparison.OrdinalIgnoreCase);
            }
        }

        public static void Set(bool enabled)
        {
            try
            {
                using (var key = Registry.CurrentUser.CreateSubKey(RunKey))
                {
                    if (enabled) key.SetValue(ValueName, Command);
                    else key.DeleteValue(ValueName, false);
                }
            }
            catch (Exception ex)
            {
                Log.Write("Could not change the start-with-Windows setting: " + ex.Message);
            }
        }
    }
}
