import Foundation

public enum Http {
    /// One shared session for the whole app (Last.fm, GitHub, iTunes Search).
    public static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = ["User-Agent": "AppleMusicScrobbler/\(AppInfo.version) (macOS)"]
        return URLSession(configuration: config)
    }()

    /// Downloads to a temporary file (for app updates).
    public static func download(_ url: URL) async throws -> (URL, URLResponse) {
        try await session.download(from: url)
    }

    /// Percent-encodes for a query string or form body (RFC 3986 unreserved characters stay as they are).
    static func escape(_ s: String) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
