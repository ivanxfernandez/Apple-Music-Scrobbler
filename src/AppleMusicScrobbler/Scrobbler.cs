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
    /// Decides when a song counts as listened (Last.fm rules: longer than 30 seconds and played for
    /// half its length or 4 minutes, whichever comes first) and delivers scrobbles, keeping a queue
    /// on disk so nothing is lost while offline. Called once a second from the UI thread.
    /// </summary>
    public class Scrobbler
    {
        const int MaxBatch = 50;
        static readonly XmlSerializer QueueSerializer = new XmlSerializer(typeof(List<QueuedScrobble>));

        readonly Settings _settings;
        readonly LastFmClient _api;
        readonly bool _dryRun;
        readonly List<QueuedScrobble> _queue;

        Play _play;
        DateTime _lastUpdate = DateTime.UtcNow;
        DateTime _nextSend = DateTime.MinValue;
        bool _sending;

        class Play
        {
            public string Key;
            public double SecondsPlayed;
            public long StartedAt;
            public double LastPosition;
            public bool NowPlayingSent;
            public bool Scrobbled;
        }

        public NowPlaying Current { get; private set; }
        public string LastScrobbled { get; private set; }
        public int Pending => _queue.Count;

        /// <summary>Raised when the Last.fm login stopped working.</summary>
        public event Action AuthProblem;

        static string QueuePath => Path.Combine(AppInfo.DataFolder, "queue.xml");

        public Scrobbler(Settings settings, LastFmClient api, bool dryRun)
        {
            _settings = settings;
            _api = api;
            _dryRun = dryRun;
            _queue = dryRun ? new List<QueuedScrobble>() : LoadQueue();
            if (_queue.Count > 0) Log.Write($"{_queue.Count} unsent scrobble(s) from last time");
        }

        public void Update(NowPlaying np)
        {
            var now = DateTime.UtcNow;
            double elapsed = (now - _lastUpdate).TotalSeconds;
            _lastUpdate = now;
            if (elapsed < 0 || elapsed > 5) elapsed = 0; // clock changed or PC was asleep

            if (_settings.CleanTitles) np = TitleCleaner.Apply(np);
            Current = np;
            if (np != null && np.IsValid)
            {
                string key = np.Artist + "\n" + np.Title + "\n" + np.Album;
                if (_play == null || _play.Key != key)
                    _play = new Play { Key = key, LastPosition = np.Position };
                else if (_play.SecondsPlayed > 30 && _play.LastPosition > 30 && np.Position < 10)
                    _play = new Play { Key = key, LastPosition = np.Position }; // same song again (repeat)
                _play.LastPosition = np.Position;

                if (np.IsPlaying)
                {
                    if (_play.StartedAt == 0) _play.StartedAt = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
                    _play.SecondsPlayed += elapsed;

                    // Wait 2 seconds so a half-updated title/artist during a track change isn't reported.
                    if (!_play.NowPlayingSent && _play.SecondsPlayed >= 2)
                    {
                        _play.NowPlayingSent = true;
                        if (!_settings.Paused) _ = SendNowPlayingAsync(np);
                    }

                    bool longEnough = np.Duration == 0 || np.Duration > 30;
                    double needed = np.Duration > 0 ? Math.Min(np.Duration / 2.0, 240) : 240;
                    if (!_play.Scrobbled && longEnough && _play.SecondsPlayed >= needed)
                    {
                        _play.Scrobbled = true;
                        if (!_settings.Paused) Enqueue(np, _play.StartedAt);
                    }
                }
            }

            if (_queue.Count > 0 && !_sending && now >= _nextSend)
                _ = SendQueueAsync();
        }

        /// <summary>Try sending queued scrobbles on the next update (e.g. after reconnecting).</summary>
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
            LastScrobbled = np.ToString();
            _nextSend = DateTime.MinValue;
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
                foreach (var s in batch) Log.Write((_dryRun ? "[dry run] Would scrobble: " : "Scrobbled: ") + $"{s.Artist} - {s.Track}");
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
