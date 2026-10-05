import Foundation

/// Keeps the Discord "Listening to" status in sync with Music. Called once a second from the
/// main thread; only talks to Discord when something visible changed.
@MainActor
public final class DiscordPresence {
    private static let reconnectSeconds = 15.0
    private static let minSecondsBetweenUpdates = 2.0   // Discord allows 5 updates per 20 seconds
    private static let maxArtworkWaitSeconds = 3.0

    private let settings: Settings
    private let links = AppleMusicLinks()
    /// Socket calls block, so they run here, one at a time.
    private let queue = DispatchQueue(label: "DiscordPresence")
    private var ipc: DiscordIpc?
    private var connecting = false
    private var connectFailureLogged = false
    private var nextConnect = Date.distantPast
    private var lastSend = Date.distantPast

    // What Discord currently shows: nil = unknown, "" = nothing.
    private var shownKey: String?
    private var shownStartMs: Int64 = 0
    private var shownWithLinks = false
    private var waitingKey: String?
    private var waitingSince = Date.distantPast

    public init(settings: Settings) {
        self.settings = settings
    }

    /// False when the app was built without a Discord application ID.
    public static var available: Bool { !AppInfo.discordClientId.isEmpty }

    public var isConnected: Bool { ipc?.isConnected == true }

    public func update(_ np: NowPlaying?) {
        guard Self.available else { return }
        guard settings.showOnDiscord else {
            if ipc != nil { disconnect() } // Discord clears the status when we disconnect
            return
        }

        if !isConnected {
            if ipc != nil {
                Log.write("Disconnected from Discord")
                disconnect()
            }
            if !connecting && Date() >= nextConnect { connect() }
            return
        }

        if Date().timeIntervalSince(lastSend) < Self.minSecondsBetweenUpdates { return }

        guard let np, np.isValid, np.isPlaying else {
            if shownKey != "" { send(nil, key: "", startMs: 0, withLinks: false) }
            return
        }

        let key = np.artist + "\n" + np.title + "\n" + np.album
        var startMs = Int64(Date().timeIntervalSince1970 * 1000) - Int64(np.position * 1000)
        let (linksReady, found) = links.tryGet(artist: np.artist, title: np.title, album: np.album)

        let changed = ActivityBuilder.needsUpdate(shownKey: shownKey, shownStartMs: shownStartMs, key: key, startMs: startMs)
        let artArrived = !changed && !shownWithLinks && linksReady && found != nil
        if !changed && !artArrived { return }

        if !linksReady {
            // Give the album art lookup a moment so the status doesn't flash without a picture.
            if waitingKey != key {
                waitingKey = key
                waitingSince = Date()
            }
            if Date().timeIntervalSince(waitingSince) < Self.maxArtworkWaitSeconds { return }
        }

        if artArrived { startMs = shownStartMs } // keep the progress bar steady
        send(ActivityBuilder.build(np, links: found, startMs: startMs, lastFmUser: settings.username),
             key: key, startMs: startMs, withLinks: linksReady && found != nil)
    }

    public func shutDown() { disconnect() }

    private func send(_ activityJson: String?, key: String, startMs: Int64, withLinks: Bool) {
        guard let ipc else { return }
        lastSend = Date()
        shownKey = key
        shownStartMs = startMs
        shownWithLinks = withLinks
        queue.async {
            do {
                try ipc.setActivity(activityJson)
            } catch {
                Log.write("Couldn't update Discord status: \(error)")
                Task { @MainActor in self.shownKey = nil }
            }
        }
    }

    private func connect() {
        connecting = true
        let ipc = DiscordIpc()
        ipc.onError = { Log.write("Discord rejected the status update: \($0)") }
        let clientId = AppInfo.discordClientId
        queue.async {
            var failure: Error?
            do { try ipc.connect(clientId: clientId) } catch { failure = error }
            Task { @MainActor in
                self.connecting = false
                if let failure {
                    ipc.close()
                    if !self.connectFailureLogged { Log.write("Discord status unavailable: \(failure)") }
                    self.connectFailureLogged = true
                    self.nextConnect = Date().addingTimeInterval(Self.reconnectSeconds)
                } else {
                    self.ipc = ipc
                    self.shownKey = nil
                    self.lastSend = .distantPast
                    self.connectFailureLogged = false
                    Log.write("Connected to Discord")
                }
            }
        }
    }

    private func disconnect() {
        if let ipc { queue.async { ipc.close() } }
        ipc = nil
        shownKey = nil
        nextConnect = Date().addingTimeInterval(Self.reconnectSeconds)
    }
}
