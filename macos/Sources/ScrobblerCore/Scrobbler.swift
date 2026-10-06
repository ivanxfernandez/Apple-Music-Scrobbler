import Foundation

/// Feeds player snapshots to the PlayTracker and delivers what it decides to Last.fm, keeping
/// a queue on disk so nothing is lost while offline. Called once a second from the main thread.
@MainActor
public final class Scrobbler {
    private static let maxBatch = 50

    private let settings: Settings
    private let api: LastFmClient
    private let dryRun: Bool
    private let queueURL: URL
    private var queue: [QueuedScrobble]

    private let tracker = PlayTracker()
    private let mainArtist: MainArtistResolver
    private var lastUpdate = Date()
    private var nextSend = Date.distantPast
    private var sending = false

    public private(set) var current: NowPlaying?
    public var lastScrobbled: String { settings.lastScrobbled }
    public var pending: Int { queue.count }
    /// The current song's artist is on the ignore list: nothing is sent for it.
    public var currentIsIgnored: Bool {
        guard let current, current.isValid else { return false }
        return IgnoreList.isIgnored(current.artist, in: settings.ignoredArtists)
    }
    /// Scrobbles waiting to be sent (offline, or Last.fm busy), oldest first.
    public var pendingScrobbles: [QueuedScrobble] { queue }
    /// Latest scrobbles Last.fm accepted, newest first.
    public var recent: [RecentScrobble] { settings.recentScrobbles }

    /// Called when the Last.fm login stopped working.
    public var onAuthProblem: (() -> Void)?
    /// Called when a song is announced as "now playing" (not while paused or for ignored artists).
    public var onNowPlaying: ((NowPlaying) -> Void)?

    /// The current song as it's sent to Last.fm: cleaned title and album, and the main artist if that option is on.
    public var currentAsSent: NowPlaying? {
        guard var np = current, np.isValid else { return nil }
        if settings.mainArtistOnly { np.artist = mainArtist.resolve(np.artist) }
        return np
    }

    public init(settings: Settings, api: LastFmClient, dryRun: Bool, folder: URL = AppInfo.dataFolder) {
        self.settings = settings
        self.api = api
        self.dryRun = dryRun
        mainArtist = MainArtistResolver(api: api)
        queueURL = folder.appendingPathComponent("queue.json")
        queue = dryRun ? [] : Self.loadQueue(queueURL)
        if !queue.isEmpty { Log.write("\(queue.count) unsent scrobble(s) from last time") }
    }

    public func update(_ snapshot: NowPlaying?) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastUpdate)
        lastUpdate = now

        let np = settings.cleanTitles ? TitleCleaner.apply(snapshot) : snapshot
        current = np

        let events = tracker.update(np, elapsedSeconds: elapsed, unixNow: Int64(now.timeIntervalSince1970))
        let paused = settings.isPaused(at: now)
        if !paused, let np, IgnoreList.isIgnored(np.artist, in: settings.ignoredArtists) {
            if events.nowPlaying { Log.write("Not scrobbling \(np) (artist is on the ignore list)") }
        } else if !paused, var np {
            // Only what's sent changes; the tracker and Discord keep the full credit.
            if settings.mainArtistOnly && np.isValid { np.artist = mainArtist.resolve(np.artist) }
            if events.nowPlaying {
                sendNowPlaying(np)
                onNowPlaying?(np)
            }
            if let startedAt = events.scrobbleAt { enqueue(np, startedAt: startedAt) }
        }

        if !queue.isEmpty && !sending && now >= nextSend { sendQueue() }
    }

    /// Queues a play found by CatchUp, with the same title cleanup, main-artist and ignore rules as
    /// live plays. Returns false if it was ignored.
    @discardableResult
    public func enqueueMissedPlay(_ play: CatchUp.Play) -> Bool {
        var np = NowPlaying(artist: play.artist, title: play.title, album: play.album, duration: play.duration, isPlaying: true)
        if IgnoreList.isIgnored(np.artist, in: settings.ignoredArtists) { return false }
        if settings.cleanTitles { np = TitleCleaner.apply(np) ?? np }
        if settings.mainArtistOnly { np.artist = mainArtist.resolve(np.artist) }
        queue.append(QueuedScrobble(artist: np.artist, track: np.title, album: np.album, duration: np.duration,
                                    timestamp: Int64(play.started.timeIntervalSince1970)))
        saveQueue()
        nextSend = .distantPast
        return true
    }

    /// Try sending queued scrobbles on the next update (e.g. after reconnecting, or "Send Now").
    public func retrySoon() { nextSend = .distantPast }

    private func sendNowPlaying(_ np: NowPlaying) {
        Log.write("Now playing: \(np)" + (np.album.isEmpty ? "" : " [\(np.album)]"))
        if dryRun { return }
        Task {
            do {
                try await api.updateNowPlaying(np)
            } catch {
                Log.write("Now-playing update failed: \(error)")
                if (error as? LastFmError)?.isAuthProblem == true { onAuthProblem?() }
            }
        }
    }

    private func enqueue(_ np: NowPlaying, startedAt: Int64) {
        queue.append(QueuedScrobble(artist: np.artist, track: np.title, album: np.album, duration: np.duration, timestamp: startedAt))
        saveQueue()
        nextSend = .distantPast
        settings.lastScrobbled = np.description
    }

    private func sendQueue() {
        sending = true
        let batch = Array(queue.prefix(Self.maxBatch))
        Task {
            defer { sending = false }
            do {
                let ignored = dryRun ? [] : try await api.scrobble(batch)
                // Only enqueue (which appends) can run meanwhile, so the batch is still at the front.
                queue.removeFirst(batch.count)
                saveQueue()
                var recent = settings.recentScrobbles
                for s in batch {
                    Log.write((dryRun ? "[dry run] Would scrobble: " : "Scrobbled: ") + "\(s.artist) - \(s.track)")
                    recent = RecentScrobbles.adding(RecentScrobble(timestamp: s.timestamp, artist: s.artist, track: s.track), to: recent)
                }
                if !dryRun { settings.recentScrobbles = recent }
                for message in ignored { Log.write("  Last.fm ignored " + message) }
            } catch {
                let lastFm = error as? LastFmError
                if let lastFm, !lastFm.isTemporary, !lastFm.isAuthProblem {
                    // Last.fm rejected the request itself; retrying the same data would fail forever.
                    queue.removeFirst(batch.count)
                    saveQueue()
                    Log.write("Last.fm rejected \(batch.count) scrobble(s): \(error)")
                    for s in batch { Log.write("  dropped: \(s.artist) - \(s.track)") }
                } else {
                    let auth = lastFm?.isAuthProblem == true
                    nextSend = Date().addingTimeInterval(auth ? 30 * 60 : 2 * 60)
                    Log.write("Couldn't scrobble, will retry (\(queue.count) waiting): \(error.localizedDescriptionIfUseful)")
                    if auth { onAuthProblem?() }
                }
            }
        }
    }

    private static func loadQueue(_ url: URL) -> [QueuedScrobble] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            return try JSONDecoder().decode([QueuedScrobble].self, from: Data(contentsOf: url))
        } catch {
            Log.write("Could not read the scrobble queue: \(error)")
            return []
        }
    }

    private func saveQueue() {
        if dryRun { return }
        do {
            try FileManager.default.createDirectory(at: queueURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(queue).write(to: queueURL, options: .atomic)
        } catch {
            Log.write("Could not save the scrobble queue: \(error)")
        }
    }
}

public extension Error {
    /// URLSession errors read better as their localized text; Last.fm errors as their own description.
    var localizedDescriptionIfUseful: String {
        self is LastFmError ? "\(self)" : localizedDescription
    }
}
