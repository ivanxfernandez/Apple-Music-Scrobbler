using System.Globalization;
using System.Text;

namespace AppleMusicScrobbler.Discord
{
    /// <summary>Just enough JSON writing for Discord payloads (no dependency on a JSON library).</summary>
    static class Json
    {
        public static string Str(string value)
        {
            if (value == null) return "null";
            var sb = new StringBuilder(value.Length + 2).Append('"');
            foreach (char c in value)
            {
                switch (c)
                {
                    case '"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\t': sb.Append("\\t"); break;
                    default:
                        if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture));
                        else sb.Append(c);
                        break;
                }
            }
            return sb.Append('"').ToString();
        }
    }
}
