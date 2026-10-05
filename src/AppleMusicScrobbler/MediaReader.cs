using System;
using System.Threading.Tasks;
using Windows.Media.Control;

namespace AppleMusicScrobbler
{
    public class NowPlaying
    {
        public string Artist { get; set; } = "";
        public string Title { get; set; } = "";
        public string Album { get; set; } = "";
        /// <summary>Track length in seconds, 0 if unknown.</summary>
        public int Duration { get; set; }
        /// <summary>Estimated playback position in seconds.</summary>
        public double Position { get; set; }
        public bool IsPlaying { get; set; }

        public bool IsValid => Artist.Length > 0 && Title.Length > 0;
        public override string ToString() => $"{Artist} - {Title}";
    }

    /// <summary>
    /// Reads what the Apple Music app is playing from the Windows media controls
    /// (the same info shown in the volume flyout / lock screen).
    /// </summary>
    public class MediaReader
    {
        const string AppleMusicAppId = "AppleInc.AppleMusic";

        // Apple Music for Windows reports the artist as "Artist — Album" and leaves the album empty.
        const string ArtistAlbumSeparator = " — ";

        GlobalSystemMediaTransportControlsSessionManager _manager;

        public async Task<NowPlaying> ReadAsync()
        {
            if (_manager == null)
                _manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();

            foreach (var session in _manager.GetSessions())
            {
                if (!(session.SourceAppUserModelId ?? "").StartsWith(AppleMusicAppId, StringComparison.OrdinalIgnoreCase))
                    continue;

                var props = await session.TryGetMediaPropertiesAsync();
                if (props == null) continue;

                var timeline = session.GetTimelineProperties();
                bool playing = session.GetPlaybackInfo()?.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing;
                var (artist, album) = SplitArtist(props.Artist, props.AlbumTitle);

                int duration = Math.Max(0, (int)Math.Round((timeline.EndTime - timeline.StartTime).TotalSeconds));
                double position = timeline.Position.TotalSeconds;
                if (playing && timeline.LastUpdatedTime.Year > 2000)
                    position += (DateTimeOffset.Now - timeline.LastUpdatedTime).TotalSeconds;
                if (duration > 0) position = Math.Min(position, duration);

                return new NowPlaying
                {
                    Artist = artist,
                    Title = (props.Title ?? "").Trim(),
                    Album = album,
                    Duration = duration,
                    Position = position,
                    IsPlaying = playing,
                };
            }
            return null;
        }

        public static (string Artist, string Album) SplitArtist(string artist, string album)
        {
            artist = (artist ?? "").Trim();
            album = (album ?? "").Trim();
            int i = artist.IndexOf(ArtistAlbumSeparator, StringComparison.Ordinal);
            if (i > 0)
            {
                if (album.Length == 0) album = artist.Substring(i + ArtistAlbumSeparator.Length).Trim();
                artist = artist.Substring(0, i).Trim();
            }
            return (artist, album);
        }
    }
}
