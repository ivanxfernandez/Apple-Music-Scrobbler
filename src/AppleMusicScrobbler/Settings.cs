using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Xml.Serialization;

namespace AppleMusicScrobbler
{
    /// <summary>
    /// Saved in %APPDATA%\AppleMusicScrobbler\settings.xml. The session key and API secret are
    /// encrypted with Windows DPAPI, so they're only readable by the same Windows user.
    /// </summary>
    public class Settings
    {
        static readonly byte[] Entropy = Encoding.UTF8.GetBytes("AppleMusicScrobbler");
        static readonly XmlSerializer Serializer = new XmlSerializer(typeof(Settings));

        /// <summary>User-supplied API key; empty means use the one built into the exe.</summary>
        public string ApiKey { get; set; } = "";
        public string Username { get; set; } = "";
        public bool Paused { get; set; }
        public bool CheckForUpdates { get; set; } = true;
        /// <summary>Remove "Remaster", "Deluxe Edition", "- Single" etc. from titles (see TitleCleaner).</summary>
        public bool CleanTitles { get; set; } = true;
        /// <summary>Last version we showed an update notification for, so it's only shown once.</summary>
        public string UpdateNotifiedFor { get; set; } = "";
        /// <summary>"Artist - Title" of the latest scrobble, shown in the tray menu.</summary>
        public string LastScrobbled { get; set; } = "";

        [XmlIgnore] public string ApiSecret { get; set; } = "";
        [XmlIgnore] public string SessionKey { get; set; } = "";

        [XmlElement("ApiSecret")]
        public string ApiSecretProtected { get => Protect(ApiSecret); set => ApiSecret = Unprotect(value); }

        [XmlElement("SessionKey")]
        public string SessionKeyProtected { get => Protect(SessionKey); set => SessionKey = Unprotect(value); }

        [XmlIgnore] public string EffectiveApiKey => string.IsNullOrEmpty(ApiKey) ? AppInfo.BuiltInApiKey : ApiKey;
        [XmlIgnore] public string EffectiveApiSecret => string.IsNullOrEmpty(ApiKey) ? AppInfo.BuiltInApiSecret : ApiSecret;
        [XmlIgnore] public bool IsConnected => SessionKey.Length > 0 && EffectiveApiKey.Length > 0;

        static string FilePath => Path.Combine(AppInfo.DataFolder, "settings.xml");

        public static Settings Load()
        {
            try
            {
                if (File.Exists(FilePath))
                    using (var stream = File.OpenRead(FilePath))
                        return (Settings)Serializer.Deserialize(stream);
            }
            catch (Exception ex)
            {
                Log.Write("Could not read settings: " + ex.Message);
            }
            return new Settings();
        }

        public void Save()
        {
            Directory.CreateDirectory(AppInfo.DataFolder);
            string temp = FilePath + ".tmp";
            using (var stream = File.Create(temp))
                Serializer.Serialize(stream, this);
            if (File.Exists(FilePath)) File.Replace(temp, FilePath, null);
            else File.Move(temp, FilePath);
        }

        static string Protect(string value) =>
            string.IsNullOrEmpty(value) ? "" :
            Convert.ToBase64String(ProtectedData.Protect(Encoding.UTF8.GetBytes(value), Entropy, DataProtectionScope.CurrentUser));

        static string Unprotect(string value)
        {
            if (string.IsNullOrEmpty(value)) return "";
            try
            {
                return Encoding.UTF8.GetString(ProtectedData.Unprotect(Convert.FromBase64String(value), Entropy, DataProtectionScope.CurrentUser));
            }
            catch
            {
                return ""; // copied from another user/PC: just reconnect
            }
        }
    }
}
