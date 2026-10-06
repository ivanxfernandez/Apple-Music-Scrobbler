import AppKit
import ScrobblerCore

/// Whether we may ask Music for its playback position (macOS Automation permission).
enum MusicAccess: Equatable {
    case unknown      // not checked yet, or Music isn't running
    case notAsked     // the user hasn't been asked yet
    case granted
    case denied
}

/// Reads what the Music app is playing.
///
/// Track info and play/pause come from Music's `com.apple.Music.playerInfo` notification, which
/// needs no permission. The playback position isn't in it, and Music posts nothing when a song
/// restarts on Repeat One, so the position is read with AppleScript once a second (Automation
/// permission). Without that permission the position is estimated by a local clock that wraps
/// at the end of the song, so a repeated song still starts a new listen.
@MainActor
final class MusicReader {
    nonisolated static let musicBundleId = "com.apple.Music"

    private struct Track: Equatable {
        var name: String
        var artist: String
        var album: String
        /// Seconds, 0 if unknown.
        var duration: Int
        var key: String { artist + "\n" + name + "\n" + album }
    }

    private var track: Track?
    private var isPlaying = false
    private var stopped = true
    /// Last known position and when it was known; while playing it advances with the clock.
    private var position = 0.0
    private var positionAt = Date()

    private(set) var access: MusicAccess = .unknown
    private var nextAccessCheck = Date.distantPast
    private var queryInFlight = false
    private var loggedDenied = false
    /// Apple Events block, so they run here, one at a time, never on the main thread.
    private let scriptQueue = DispatchQueue(label: "MusicReader.applescript")

    var onAccessChanged: (() -> Void)?

    init() {
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo ?? [:]
            MainActor.assumeIsolated { self?.handle(info) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Self.musicBundleId else { return }
            MainActor.assumeIsolated {
                self?.track = nil
                self?.isPlaying = false
                self?.stopped = true
            }
        }
    }

    nonisolated static var musicIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: musicBundleId).isEmpty
    }

    /// What's playing right now, or nil when nothing is. Call once a second.
    func snapshot() -> NowPlaying? {
        guard Self.musicIsRunning else { return nil }
        refreshAccess()
        if access == .granted { queryPosition() }

        guard let track, !stopped else { return nil }
        return NowPlaying(artist: track.artist, title: track.name, album: track.album,
                          duration: track.duration, position: currentPosition(), isPlaying: isPlaying)
    }

    /// Shows the macOS "wants to control Music" prompt (if it hasn't been answered yet). Starts Music if needed.
    func requestAccess() async -> MusicAccess {
        if !Self.musicIsRunning, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.musicBundleId) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
            for _ in 0..<20 where !Self.musicIsRunning { try? await Task.sleep(nanoseconds: 250_000_000) }
        }
        let status = await withCheckedContinuation { continuation in
            scriptQueue.async { continuation.resume(returning: Self.permission(ask: true)) }
        }
        setAccess(Self.access(from: status))
        if access == .granted { loadCurrentTrack() }
        return access
    }

    // MARK: - Notifications

    private func handle(_ info: [AnyHashable: Any]) {
        advanceClock()
        let state = info["Player State"] as? String ?? ""
        if let name = info["Name"] as? String {
            let totalMs = (info["Total Time"] as? NSNumber)?.doubleValue ?? 0
            let new = Track(name: name, artist: info["Artist"] as? String ?? "", album: info["Album"] as? String ?? "",
                            duration: Int((totalMs / 1000).rounded()))
            // Music refines Total Time while a song plays, so a different duration isn't a new song.
            if track?.key != new.key { setPosition(0) }
            track = new
        }
        isPlaying = state == "Playing"
        stopped = state == "Stopped"
    }

    // MARK: - Position

    private func currentPosition() -> Double {
        advanceClock()
        return position
    }

    /// Moves the position forward by the time played since it was last known, wrapping at the end
    /// of the song (that's what Music does on Repeat One, without telling anyone).
    private func advanceClock() {
        let now = Date()
        if isPlaying && !stopped {
            position += now.timeIntervalSince(positionAt)
            if let duration = track?.duration, duration > 0, position >= Double(duration) {
                position = position.truncatingRemainder(dividingBy: Double(duration))
            }
        }
        positionAt = now
    }

    private func setPosition(_ seconds: Double) {
        position = max(0, seconds)
        positionAt = Date()
    }

    private func queryPosition() {
        guard !queryInFlight, isPlaying, track != nil else { return }
        queryInFlight = true
        let expectedKey = track?.key
        scriptQueue.async {
            let result = Self.run("get player position")
            Task { @MainActor in
                self.queryInFlight = false
                switch result {
                case .success(let descriptor):
                    // Ignore an answer about a song that changed while we were asking.
                    if self.track?.key == expectedKey { self.setPosition(descriptor.doubleValue) }
                case .failure(let error):
                    if error.code == -1743 || error.code == -1744 { self.setAccess(Self.access(from: OSStatus(error.code))) }
                }
            }
        }
    }

    /// With permission, read the current song once at launch, since Music only posts a
    /// notification when something changes.
    func loadCurrentTrack() {
        guard Self.musicIsRunning, access == .granted else { return }
        scriptQueue.async {
            let result = Self.run("""
                set s to player state as text
                if s is "stopped" then return {s}
                set t to current track
                return {s, name of t, artist of t, album of t, duration of t, player position}
                """)
            Task { @MainActor in
                guard case .success(let list) = result, list.numberOfItems >= 1 else { return }
                let state = list.atIndex(1)?.stringValue ?? "stopped"
                if list.numberOfItems >= 6, self.track == nil {
                    self.track = Track(name: list.atIndex(2)?.stringValue ?? "", artist: list.atIndex(3)?.stringValue ?? "",
                                       album: list.atIndex(4)?.stringValue ?? "", duration: Int((list.atIndex(5)?.doubleValue ?? 0).rounded()))
                    self.setPosition(list.atIndex(6)?.doubleValue ?? 0)
                    self.isPlaying = state == "playing"
                    self.stopped = false
                }
            }
        }
    }

    // MARK: - Permission

    private func refreshAccess() {
        guard access != .granted, Date() >= nextAccessCheck else { return }
        nextAccessCheck = Date().addingTimeInterval(5) // the user may allow it in System Settings meanwhile
        scriptQueue.async {
            let status = Self.permission(ask: false)
            Task { @MainActor in
                let wasGranted = self.access == .granted
                self.setAccess(Self.access(from: status))
                if !wasGranted && self.access == .granted { self.loadCurrentTrack() }
            }
        }
    }

    private func setAccess(_ new: MusicAccess) {
        guard new != access else { return }
        access = new
        switch new {
        case .granted: Log.write("Allowed to read Music's playback position")
        case .denied where !loggedDenied:
            loggedDenied = true
            Log.write("Not allowed to read Music's playback position; estimating it instead (repeats may be missed after seeking)")
        case .notAsked: Log.write("Music access not asked yet; estimating the playback position until it's allowed")
        default: break
        }
        onAccessChanged?()
    }

    private nonisolated static func access(from status: OSStatus) -> MusicAccess {
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
        default: return .unknown // procNotFound: Music isn't running
        }
    }

    private nonisolated static func permission(ask: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: musicBundleId)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
    }

    private struct ScriptError: Error { let code: Int }

    /// Runs AppleScript inside `tell application "Music"`, giving up after 2 seconds.
    private nonisolated static func run(_ body: String) -> Result<NSAppleEventDescriptor, ScriptError> {
        // Never launch Music just to ask it something.
        guard musicIsRunning else { return .failure(ScriptError(code: -600)) }
        let source = "with timeout of 2 seconds\ntell application id \"\(musicBundleId)\"\n\(body)\nend tell\nend timeout"
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let result, error == nil { return .success(result) }
        return .failure(ScriptError(code: (error?[NSAppleScript.errorNumber] as? Int) ?? -1))
    }
}

extension NSFont {
    var bold: NSFont { NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask) }
}

extension MusicReader {
    /// Library songs whose latest play ended after `since` (Music's "played date"), including plays
    /// on other devices synced through iCloud. Needs Music access; nil if Music isn't running or it failed.
    func recentLibraryPlays(since: Date) async -> [CatchUp.Play]? {
        guard Self.musicIsRunning, access == .granted else { return nil }
        let seconds = max(0, Int(Date().timeIntervalSince(since)))
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let source = """
                    with timeout of 30 seconds
                    tell application id "\(Self.musicBundleId)"
                    set r to a reference to (every track of library playlist 1 whose played date > ((current date) - \(seconds)))
                    if (count of r) is 0 then return {}
                    return {name of r, artist of r, album of r, duration of r, played date of r}
                    end tell
                    end timeout
                    """
                var error: NSDictionary?
                guard Self.musicIsRunning, let result = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil else {
                    if let error { Log.write("Couldn't read Music's play history: \(error[NSAppleScript.errorMessage] ?? error)") }
                    continuation.resume(returning: nil)
                    return
                }
                guard result.numberOfItems == 5, let names = result.atIndex(1), let artists = result.atIndex(2), let albums = result.atIndex(3),
                      let durations = result.atIndex(4), let dates = result.atIndex(5) else {
                    continuation.resume(returning: [])
                    return
                }
                var plays: [CatchUp.Play] = []
                for i in stride(from: 1, through: names.numberOfItems, by: 1) {
                    guard let date = dates.atIndex(i)?.dateValue else { continue }
                    plays.append(CatchUp.Play(artist: artists.atIndex(i)?.stringValue ?? "", title: names.atIndex(i)?.stringValue ?? "",
                                              album: albums.atIndex(i)?.stringValue ?? "", duration: Int((durations.atIndex(i)?.doubleValue ?? 0).rounded()),
                                              playedDate: date))
                }
                continuation.resume(returning: plays)
            }
        }
    }
}
