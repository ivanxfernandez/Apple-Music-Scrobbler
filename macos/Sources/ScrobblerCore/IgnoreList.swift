import Foundation

/// Artists the user doesn't want scrobbled (or shown on Discord). Matching ignores case, accents
/// and punctuation, and a collaboration counts as its first artist too: ignoring "Joji" also
/// covers "Joji & BENEE".
public enum IgnoreList {
    public static func isIgnored(_ artist: String, in list: [String]) -> Bool {
        guard !list.isEmpty, !artist.isEmpty else { return false }
        let ignored = Set(list.map { AppleMusicLinks.normalize($0) }.filter { !$0.isEmpty })
        if ignored.contains(AppleMusicLinks.normalize(artist)) { return true }
        if let first = MainArtist.firstArtist(artist), ignored.contains(AppleMusicLinks.normalize(first)) { return true }
        return false
    }

    /// The list with the artist added (unless it's already covered), sorted for the menu.
    public static func adding(_ artist: String, to list: [String]) -> [String] {
        let name = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || list.contains(where: { AppleMusicLinks.normalize($0) == AppleMusicLinks.normalize(name) }) { return list }
        return (list + [name]).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public static func removing(_ artist: String, from list: [String]) -> [String] {
        list.filter { AppleMusicLinks.normalize($0) != AppleMusicLinks.normalize(artist) }
    }
}
