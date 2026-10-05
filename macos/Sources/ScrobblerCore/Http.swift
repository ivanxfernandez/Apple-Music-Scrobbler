import Foundation

enum Http {
    /// One shared session for the whole app (Last.fm, GitHub, iTunes Search).
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = ["User-Agent": "AppleMusicScrobbler/\(AppInfo.version) (macOS)"]
        return URLSession(configuration: config)
    }()

    /// Percent-encodes for a query string or form body (RFC 3986 unreserved characters stay as they are).
    static func escape(_ s: String) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
