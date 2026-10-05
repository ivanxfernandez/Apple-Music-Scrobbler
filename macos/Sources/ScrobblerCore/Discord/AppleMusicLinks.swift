import Foundation

/// Finds album art and Apple Music links for a track with Apple's public iTunes Search API
/// (the Music app doesn't give out artwork as a URL Discord can show). Results are cached.
@MainActor
public final class AppleMusicLinks {
    public struct SearchResult: Decodable, Equatable {
        public var artistName: String?
        public var trackName: String?
        public var collectionName: String?
        public var artworkUrl100: String?
        public var trackViewUrl: String?
        public var collectionViewUrl: String?
        public var artistViewUrl: String?

        public init(artistName: String?, trackName: String?, collectionName: String?) {
            self.artistName = artistName
            self.trackName = trackName
            self.collectionName = collectionName
        }
    }

    private struct SearchResponse: Decodable {
        let results: [SearchResult]?
    }

    private static let maxCacheEntries = 500
    /// nil value = looked up, nothing found.
    private var cache: [String: TrackLinks?] = [:]
    private var pending: Set<String> = []

    public init() {}

    /// Returns (true, links or nil if nothing was found) once the lookup has finished;
    /// (false, nil) while it's still running. Starts the lookup on first call.
    public func tryGet(artist: String, title: String, album: String) -> (ready: Bool, links: TrackLinks?) {
        let key = artist + "\n" + title + "\n" + album
        if let links = cache[key] { return (true, links) }
        if !pending.contains(key) {
            pending.insert(key)
            Task {
                var links: TrackLinks?
                do {
                    links = try await Self.lookup(artist: artist, title: title, album: album)
                } catch {
                    Log.write("Album art lookup failed: \(error.localizedDescription)")
                }
                if cache.count >= Self.maxCacheEntries { cache.removeAll() }
                cache[key] = .some(links)
                pending.remove(key)
            }
        }
        return (false, nil)
    }

    private static func lookup(artist: String, title: String, album: String) async throws -> TrackLinks? {
        let songs = try await search("song", artist + " " + title)
        let song = bestMatch(songs, artist: artist, title: title, album: album)
        // Song not found but its album is: the art and album/artist links are still right.
        var source = song ?? albumMatch(songs, artist: artist, album: album)
        if source == nil && !album.isEmpty {
            source = albumMatch(try await search("album", artist + " " + album), artist: artist, album: album)
        }
        guard let source else { return nil }

        return TrackLinks(
            // artworkUrl100 ends in ".../100x100bb.jpg"; the same path serves bigger sizes.
            artworkUrl: source.artworkUrl100?.replacingOccurrences(of: "100x100bb", with: "512x512bb"),
            trackUrl: song?.trackViewUrl,
            albumUrl: source.collectionViewUrl,
            artistUrl: source.artistViewUrl)
    }

    private static func search(_ entity: String, _ term: String) async throws -> [SearchResult] {
        let url = URL(string: "https://itunes.apple.com/search?media=music&entity=\(entity)&limit=15&country=\(country())&term=\(Http.escape(term))")!
        let (body, response) = try await Http.session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return try JSONDecoder().decode(SearchResponse.self, from: body).results ?? []
    }

    private static func country() -> String {
        let code = Locale.current.region?.identifier ?? ""
        return code.count == 2 && code.allSatisfy(\.isLetter) ? code.lowercased() : "us"
    }

    /// A result from the same artist and album (any song), or nil.
    public nonisolated static func albumMatch(_ results: [SearchResult]?, artist: String, album: String) -> SearchResult? {
        let a = normalize(artist), al = normalize(album)
        if al.isEmpty { return nil }
        return (results ?? []).first { similar(normalize($0.artistName), a) && normalize($0.collectionName) == al }
    }

    /// The same song (artist and title must match), preferring the right album; or nil.
    public nonisolated static func bestMatch(_ results: [SearchResult]?, artist: String, title: String, album: String) -> SearchResult? {
        let a = normalize(artist), t = normalize(title), al = normalize(album)
        var best: SearchResult?
        var bestScore = 0
        for r in results ?? [] {
            if !similar(normalize(r.artistName), a) { continue } // wrong artist: never use
            let rt = normalize(r.trackName), ral = normalize(r.collectionName)
            var score: Int
            if rt == t { score = 4 } else if similar(rt, t) { score = 2 } else { continue } // different song
            if !al.isEmpty && ral == al { score += 3 } else if !al.isEmpty && similar(ral, al) { score += 1 }
            if score > bestScore { best = r; bestScore = score }
        }
        return best
    }

    private nonisolated static func similar(_ x: String, _ y: String) -> Bool {
        !x.isEmpty && !y.isEmpty && (x.contains(y) || y.contains(x))
    }

    /// Lowercase letters and digits only (accents removed), so punctuation/casing differences don't matter.
    nonisolated static func normalize(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "" }
        var out = String.UnicodeScalarView()
        for scalar in s.decomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber:
                out.append(contentsOf: String(scalar).lowercased().unicodeScalars)
            default:
                continue // marks (accents), punctuation, spaces, symbols
            }
        }
        return String(out)
    }
}
