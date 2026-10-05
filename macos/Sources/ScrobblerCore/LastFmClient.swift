import CryptoKit
import Foundation

public struct LastFmError: Error, CustomStringConvertible {
    /// Last.fm error code (https://www.last.fm/api/errorcodes), 0 if the response wasn't understood.
    public let code: Int
    public let message: String

    public var description: String { code > 0 ? "\(message) (Last.fm error \(code))" : message }

    /// Session or API key no longer valid: the user needs to reconnect.
    public var isAuthProblem: Bool { [4, 9, 10, 26].contains(code) }

    /// Last.fm is down or busy: try again later.
    public var isTemporary: Bool { [0, 8, 11, 16, 29].contains(code) }
}

public struct QueuedScrobble: Codable, Equatable {
    public var artist: String
    public var track: String
    public var album: String
    public var duration: Int
    /// Unix time the track started playing.
    public var timestamp: Int64

    public init(artist: String, track: String, album: String, duration: Int, timestamp: Int64) {
        self.artist = artist
        self.track = track
        self.album = album
        self.duration = duration
        self.timestamp = timestamp
    }
}

/// Minimal client for the Last.fm 2.0 API (https://www.last.fm/api).
public final class LastFmClient {
    private static let apiUrl = URL(string: "https://ws.audioscrobbler.com/2.0/")!

    private let settings: Settings

    public init(settings: Settings) {
        self.settings = settings
    }

    public func getToken() async throws -> String {
        let response = try await call("auth.getToken", [:], withSession: false)
        return text(response, "token")
    }

    /// The page where the user approves this app for their account.
    public func authUrl(token: String) -> URL {
        URL(string: "https://www.last.fm/api/auth/?api_key=\(Http.escape(settings.effectiveApiKey))&token=\(Http.escape(token))")!
    }

    /// Throws LastFmError code 14 until the user has approved the token.
    public func getSession(token: String) async throws -> (key: String, username: String) {
        let response = try await call("auth.getSession", ["token": token], withSession: false)
        return (text(response, "session/key"), text(response, "session/name"))
    }

    public func updateNowPlaying(_ track: NowPlaying) async throws {
        _ = try await call("track.updateNowPlaying", [
            "artist": track.artist,
            "track": track.title,
            "album": track.album,
            "duration": track.duration > 0 ? String(track.duration) : "",
        ], withSession: true)
    }

    public func love(artist: String, title: String) async throws {
        _ = try await call("track.love", ["artist": artist, "track": title], withSession: true)
    }

    /// How many people listen to an artist on Last.fm (exact name, no autocorrect); 0 if Last.fm doesn't know it.
    public func artistListeners(_ artist: String) async throws -> Int {
        let url = URL(string: "\(Self.apiUrl.absoluteString)?method=artist.getInfo&autocorrect=0&artist=\(Http.escape(artist))&api_key=\(Http.escape(settings.effectiveApiKey))")!
        let (body, response) = try await Http.session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let root = (try? XMLDocument(data: body))?.rootElement() else {
            throw LastFmError(code: 0, message: "Unexpected response from Last.fm (HTTP \(status))")
        }
        if root.attribute(forName: "status")?.stringValue == "ok" { return Int(text(root, "artist/stats/listeners")) ?? 0 }
        let code = Int(root.elements(forName: "error").first?.attribute(forName: "code")?.stringValue ?? "") ?? 0
        if code == 6 { return 0 } // artist not found
        throw LastFmError(code: code, message: root.elements(forName: "error").first?.stringValue ?? "Unknown Last.fm error")
    }

    /// Sends up to 50 scrobbles. Returns a description of each one Last.fm accepted but ignored.
    public func scrobble(_ batch: [QueuedScrobble]) async throws -> [String] {
        var args: [String: String] = [:]
        for (i, s) in batch.enumerated() {
            args["artist[\(i)]"] = s.artist
            args["track[\(i)]"] = s.track
            args["timestamp[\(i)]"] = String(s.timestamp)
            args["album[\(i)]"] = s.album
            if s.duration > 0 { args["duration[\(i)]"] = String(s.duration) }
        }

        let response = try await call("track.scrobble", args, withSession: true)

        var ignored: [String] = []
        for scrobble in (try? response.nodes(forXPath: "scrobbles/scrobble")) as? [XMLElement] ?? [] {
            let code = (try? scrobble.nodes(forXPath: "ignoredMessage/@code").first?.stringValue) ?? nil
            if let code, !code.isEmpty, code != "0" {
                ignored.append("\(text(scrobble, "artist")) - \(text(scrobble, "track")) (reason \(code): \(Self.ignoredReason(code)))")
            }
        }
        return ignored
    }

    private static func ignoredReason(_ code: String) -> String {
        switch code {
        case "1": return "artist ignored"
        case "2": return "track ignored"
        case "3": return "timestamp too old"
        case "4": return "timestamp too new"
        case "5": return "daily scrobble limit reached"
        default: return "unknown"
        }
    }

    private func text(_ element: XMLElement, _ path: String) -> String {
        ((try? element.nodes(forXPath: path).first?.stringValue) ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func call(_ method: String, _ args: [String: String], withSession: Bool) async throws -> XMLElement {
        var parameters = ["method": method, "api_key": settings.effectiveApiKey]
        if withSession { parameters["sk"] = settings.sessionKey }
        for (key, value) in args where !value.isEmpty { parameters[key] = value }
        parameters["api_sig"] = Self.sign(parameters, secret: settings.effectiveApiSecret)

        var request = URLRequest(url: Self.apiUrl)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(parameters.sorted { $0.key < $1.key }
            .map { "\(Http.escape($0.key))=\(Http.escape($0.value))" }
            .joined(separator: "&").utf8)

        let (body, response) = try await Http.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let root = (try? XMLDocument(data: body))?.rootElement() else {
            throw LastFmError(code: 0, message: "Unexpected response from Last.fm (HTTP \(status))")
        }
        if root.attribute(forName: "status")?.stringValue == "ok" { return root }

        let error = root.elements(forName: "error").first
        let code = Int(error?.attribute(forName: "code")?.stringValue ?? "") ?? 0
        let message = error?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        throw LastFmError(code: code, message: message.isEmpty ? "Unknown Last.fm error" : message)
    }

    /// Last.fm request signature: every parameter as name+value, sorted by name (byte order),
    /// followed by the shared secret, MD5-hashed as UTF-8.
    public static func sign(_ parameters: [String: String], secret: String) -> String {
        var toSign = ""
        for (key, value) in parameters.sorted(by: { Array($0.key.utf8).lexicographicallyPrecedes(Array($1.key.utf8)) }) {
            toSign += key + value
        }
        toSign += secret
        return Insecure.MD5.hash(data: Data(toSign.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
