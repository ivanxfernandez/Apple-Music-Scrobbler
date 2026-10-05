using System;
using System.IO;
using System.Text;

namespace AppleMusicScrobbler
{
    static class Log
    {
        static readonly object Gate = new object();

        public static string FilePath => Path.Combine(AppInfo.DataFolder, "scrobbler.log");

        public static void Write(string message)
        {
            lock (Gate)
            {
                try
                {
                    Directory.CreateDirectory(AppInfo.DataFolder);
                    var file = new FileInfo(FilePath);
                    if (file.Exists && file.Length > 1_000_000)
                    {
                        File.Copy(FilePath, FilePath + ".old", true);
                        File.Delete(FilePath);
                    }
                    File.AppendAllText(FilePath, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss}  {message}\r\n", Encoding.UTF8);
                }
                catch
                {
                    // Logging must never take the app down.
                }
            }
        }
    }
}
