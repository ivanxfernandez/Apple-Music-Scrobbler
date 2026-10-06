import Foundation

/// Strips release-version noise that Apple Music adds to names, so scrobbles land on the same
/// Last.fm track/album pages as everyone else's (instead of splitting your play counts):
///   "Locomotive (Complicity) [2022 Remaster]"  -> "Locomotive (Complicity)"
///   "Here Comes the Sun - Remastered 2009"     -> "Here Comes the Sun"
///   "Use Your Illusion II (Deluxe Edition)"    -> "Use Your Illusion II"   (album)
///   "Espresso - Single"                         -> "Espresso"               (album)
/// "feat." credits, live/acoustic versions, remixes etc. are left alone. Same patterns as TitleCleaner.cs.
public enum TitleCleaner {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    // "(2011 Remaster)", "[Remastered 2009]", "(2009 Digital Remaster)", "(Remastered Version)", "(2019 Digital Master)"
    private static let bracketedRemaster = regex(#"\s*[\(\[][^\(\)\[\]]*\b(remaster(ed)?|digital master)\b[^\(\)\[\]]*[\)\]]"#)

    // " - 2011 Remaster", " - Remastered 2009", " - 2015 Remastered Version" (last dash-separated part only)
    private static let dashedRemaster = regex(#"\s+[-–—]\s+[^-–—]*\b(remaster(ed)?|digital master)\b[^-–—]*$"#)

    // Albums: "(Deluxe Edition)", "[Expanded Version]", "(20th Anniversary Edition)", "(Bonus Track Version)"
    private static let albumEdition = regex(
        #"\s*[\(\[][^\(\)\[\]]*\b(deluxe|expanded|bonus tracks?|anniversary|special edition|collector'?s edition|legacy edition)\b[^\(\)\[\]]*[\)\]]"#)

    // Albums: " - Single", " - EP"
    private static let singleOrEp = regex(#"\s+-\s+(single|ep)$"#)

    public static func cleanTitle(_ title: String) -> String { clean(title, [bracketedRemaster, dashedRemaster]) }

    public static func cleanAlbum(_ album: String) -> String { clean(album, [bracketedRemaster, dashedRemaster, albumEdition, singleOrEp]) }

    public static func apply(_ np: NowPlaying?) -> NowPlaying? {
        guard var np else { return nil }
        np.title = cleanTitle(np.title)
        np.album = cleanAlbum(np.album)
        return np
    }

    private static func clean(_ text: String, _ patterns: [NSRegularExpression]) -> String {
        if text.isEmpty { return text }
        var result = text
        for pattern in patterns {
            result = pattern.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? text : result // never clean a name down to nothing
    }
}
