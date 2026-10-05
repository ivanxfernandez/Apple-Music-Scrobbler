using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Xml.Serialization;

namespace AppleMusicScrobbler
{
    public class QueuedScrobble
    {
        public string Artist { get; set; }
        public string Track { get; set; }
        public string Album { get; set; }
        public int Duration { get; set; }
        /// <summary>Unix time the track started playing.</summary>
        public long Timestamp { get; set; }
    }

    /// <summary>
    /// Feeds player snapshots to the PlayTracker and delivers what it decides to Last.fm, keeping
    /// a queue on disk so nothing is lost while offline. Called once a second from the UI thread.
    /// </summary>
    public class Scrobbler
    {
        const int MaxBatch = 50;
        static readonly XmlSerializer QueueSerializer = new XmlSerializer(typeof(List<QueuedScrobble>));

        readonly Settings _settings;
        readonly LastFmClient _api;
        readonly bool _dryRun;
        readonly List<QueuedScrobble> _queue;

        readonly PlayTracker _tracker = new PlayTracker();
        readonly MainArtistResolver _mainArtist;
        DateTime _lastUpdate = DateTime.UtcNow;
        DateTime _nextSend = DateTime.MinValue;
        bool _sending;

        public NowPlaying Current { get; private set; }
        public string LastScrobbled => _settings.LastScrobbled;
        public int Pending => _queue.Count;
        /// <summary>Scrobbles waiting to be sent (offline, or Last.fm busy), oldest first.</summary>
        public IReadOnlyList<QueuedScrobble> PendingScrobbles => _queue;
        /// <summary>Latest scrobbles Last.fm accepted, newest first.</summary>
        public IReadOnlyList<RecentScrobble> Recent => _settings.RecentScrobbles;

        /// <summary>Raised when the Last.fm login stopped working.</summary>
        public event Action AuthProblem;

        static string QueuePath => Path.Combine(AppInfo.DataFolder, "queue.xml");

        public Scrobbler(Settings settings, LastFmClient api, bool dryRun)
        {
            _settings = settings;
            _api = api;
            _dryRun = dryRun;
            _mainArtist = new MainArtistResolver(api);
            _queue = dryRun ? new List<QueuedScrobble>() : LoadQueue();
            if (_queue.Count > 0) Log.Write($"{_queue.Count} unsent scrobble(s) from last time");
        }

        public void Update(NowPlaying np)
        {
            var now = DateTime.UtcNow;
            double elapsed = (now - _lastUpdate).TotalSeconds;
            _lastUpdate = now;

            if (_settings.CleanTitles) np = TitleCleaner.Apply(np);
            Current = np;

            var events = _tracker.Update(np, elapsed, DateTimeOffset.UtcNow.ToUnixTimeSeconds());
            if (!_settings.Paused && np != null)
            {
                // Only what's sent changes; the tracker and Discord keep the full credit.
                var output = np;
                if (_settings.MainArtistOnly && np.IsValid)
                    output = new NowPlaying
                    {
                        Artist = _mainArtist.Resolve(np.Artist),
                        Title = np.Title,
                        Album = np.Album,
                        Duration = np.Duration,
                        Position = np.Position,
                        IsPlaying = np.IsPlaying,
                    };
                if (events.NowPlaying) _ = SendNowPlayingAsync(output);
                if (events.ScrobbleAt.HasValue) Enqueue(output, events.ScrobbleAt.Value);
            }

            if (_queue.Count > 0 && !_sending && now >= _nextSend)
                _ = SendQueueAsync();
        }

        /// <summary>Try sending queued scrobbles on the next update (e.g. after reconnecting, or "Send now").</summary>
        public void RetrySoon() => _nextSend = DateTime.MinValue;

        async Task SendNowPlayingAsync(NowPlaying np)
        {
            Log.Write($"Now playing: {np}" + (np.Album.Length > 0 ? $" [{np.Album}]" : ""));
            if (_dryRun) return;
            try
            {
                await _api.UpdateNowPlayingAsync(np);
            }
            catch (Exception ex)
            {
                Log.Write("Now-playing update failed: " + ex.Message);
                if ((ex as LastFmException)?.IsAuthProblem == true) AuthProblem?.Invoke();
            }
        }

        void Enqueue(NowPlaying np, long startedAt)
        {
            _queue.Add(new QueuedScrobble
            {
                Artist = np.Artist,
                Track = np.Title,
                Album = np.Album,
                Duration = np.Duration,
                Timestamp = startedAt,
            });
            SaveQueue();
            _nextSend = DateTime.MinValue;

            _settings.LastScrobbled = np.ToString();
            if (!_dryRun)
            {
                try { _settings.Save(); }
                catch (Exception ex) { Log.Write("Could not save settings: " + ex.Message); }
            }
        }

        async Task SendQueueAsync()
        {
            _sending = true;
            var batch = _queue.Take(MaxBatch).ToList();
            try
            {
                var ignored = _dryRun ? new List<string>() : await _api.ScrobbleAsync(batch);
                // Only Enqueue (which appends) can run meanwhile, so the batch is still at the front.
                _queue.RemoveRange(0, batch.Count);
                SaveQueue();
                var recent = _settings.RecentScrobbles;
                foreach (var s in batch)
                {
                    Log.Write((_dryRun ? "[dry run] Would scrobble: " : "Scrobbled: ") + $"{s.Artist} - {s.Track}");
                    recent = RecentScrobbles.Adding(new RecentScrobble { Timestamp = s.Timestamp, Artist = s.Artist, Track = s.Track }, recent);
                }
                if (!_dryRun)
                {
                    _settings.RecentScrobbles = recent;
                    try { _settings.Save(); }
                    catch (Exception ex) { Log.Write("Could not save settings: " + ex.Message); }
                }
                foreach (var message in ignored) Log.Write("  Last.fm ignored " + message);
            }
            catch (Exception ex)
            {
                var lastFm = ex as LastFmException;
                if (lastFm != null && !lastFm.IsTemporary && !lastFm.IsAuthProblem)
                {
                    // Last.fm rejected the request itself; retrying the same data would fail forever.
                    _queue.RemoveRange(0, batch.Count);
                    SaveQueue();
                    Log.Write($"Last.fm rejected {batch.Count} scrobble(s): {ex.Message}");
                    foreach (var s in batch) Log.Write($"  dropped: {s.Artist} - {s.Track}");
                }
                else
                {
                    bool auth = lastFm?.IsAuthProblem == true;
                    _nextSend = DateTime.UtcNow.AddMinutes(auth ? 30 : 2);
                    Log.Write($"Couldn't scrobble, will retry ({_queue.Count} waiting): {ex.Message}");
                    if (auth) AuthProblem?.Invoke();
                }
            }
            finally
            {
                _sending = false;
            }
        }

        static List<QueuedScrobble> LoadQueue()
        {
            try
            {
                if (File.Exists(QueuePath))
                    using (var stream = File.OpenRead(QueuePath))
                        return (List<QueuedScrobble>)QueueSerializer.Deserialize(stream);
            }
            catch (Exception ex)
            {
                Log.Write("Could not read the scrobble queue: " + ex.Message);
            }
            return new List<QueuedScrobble>();
        }

        void SaveQueue()
        {
            if (_dryRun) return;
            try
            {
                Directory.CreateDirectory(AppInfo.DataFolder);
                string temp = QueuePath + ".tmp";
                using (var stream = File.Create(temp))
                    QueueSerializer.Serialize(stream, _queue);
                if (File.Exists(QueuePath)) File.Replace(temp, QueuePath, null);
                else File.Move(temp, QueuePath);
            }
            catch (Exception ex)
            {
                Log.Write("Could not save the scrobble queue: " + ex.Message);
            }
        }
    }
}
