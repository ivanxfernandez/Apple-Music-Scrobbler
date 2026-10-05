import Foundation

/// "Scrobble only the main artist": Apple Music credits collaborations as one artist
/// ("Joji & BENEE"), which Last.fm counts as a separate artist from "Joji". Band names look the
/// same ("Simon & Garfunkel"), so Last.fm's own listener counts decide: a collaboration's combined
/// name has a tiny fraction of the first artist's listeners (under 2% in every case checked),
/// while a band's name has far more listeners than its first word.
public enum MainArtist {
    /// The full credit must have fewer than this share of the first artist's listeners.
    public static let maxShare = 0.10

    /// The first artist of a credit like "A & B" or "A, B & C", or nil if there's only one.
    public static func firstArtist(_ artist: String) -> String? {
        let separators = [" & ", ", "]
        guard let cut = separators.compactMap({ artist.range(of: $0)?.lowerBound }).min() else { return nil }
        let first = artist[..<cut].trimmingCharacters(in: .whitespaces)
        return first.isEmpty ? nil : first
    }

    /// True when the credit is a collaboration that should be scrobbled as its first artist.
    public static func isCollaboration(fullListeners: Int, firstListeners: Int) -> Bool {
        firstListeners > 0 && Double(fullListeners) < Double(firstListeners) * maxShare
    }
}

/// Looks up and remembers which credits are collaborations. Call `resolve` once a second;
/// it starts the Last.fm lookups the first time it sees a credit.
@MainActor
public final class MainArtistResolver {
    private let api: LastFmClient
    /// Credit → artist to scrobble.
    private var cache: [String: String] = [:]
    private var pending: Set<String> = []

    public init(api: LastFmClient) {
        self.api = api
    }

    /// The artist to scrobble for this credit: the main artist once Last.fm confirmed it's a
    /// collaboration, otherwise the credit itself (also while the lookup is running).
    public func resolve(_ artist: String) -> String {
        if let known = cache[artist] { return known }
        guard let first = MainArtist.firstArtist(artist) else { return artist }
        if !pending.contains(artist) {
            pending.insert(artist)
            Task {
                var result = artist
                do {
                    async let full = api.artistListeners(artist)
                    async let main = api.artistListeners(first)
                    let (fullCount, mainCount) = try await (full, main)
                    if MainArtist.isCollaboration(fullListeners: fullCount, firstListeners: mainCount) {
                        result = first
                        Log.write("Collaboration: scrobbling \"\(artist)\" as \"\(first)\"")
                    }
                } catch {
                    Log.write("Couldn't check whether \"\(artist)\" is a collaboration: \(error.localizedDescriptionIfUseful)")
                }
                if cache.count > 500 { cache.removeAll() }
                cache[artist] = result
                pending.remove(artist)
            }
        }
        return artist
    }
}
