import Testing
@testable import ScrobblerCore

@Suite struct MainArtistTests {
    @Test(arguments: [
        ("Joji & BENEE", "Joji" as String?),
        ("twenty one pilots, Arcane & League of Legends Music", "twenty one pilots"),
        ("Earth, Wind & Fire", "Earth"),
        ("$uicideboy$ & Germ", "$uicideboy$"),
        ("Joji", nil),
        ("AC/DC", nil),
        ("Florence + the Machine", nil),
        (" & Someone", nil),
    ])
    func findsTheFirstArtist(credit: String, expected: String?) {
        #expect(MainArtist.firstArtist(credit) == expected)
    }

    // Real Last.fm listener counts (October 2026): full credit, first artist alone.
    @Test(arguments: [
        ("Joji & BENEE", 14_247, 3_177_868, true),
        ("Anyma & Joji", 1_418, 554_429, true),
        ("Post Malone & Swae Lee", 68_630, 3_713_875, true),
        ("Héctor Lavoe & Willie Colón", 1_763, 259_791, true),
        ("twenty one pilots, Arcane & League of Legends Music", 3_598, 3_567_492, true),
        ("Los Flakos & te vi en un planetario", 79, 16_000, true),
        ("Simon & Garfunkel", 3_552_026, 62_545, false),
        ("Earth, Wind & Fire", 3_090_285, 336_393, false),
        ("Tyler, The Creator", 4_517_543, 22_586, false),
        ("Hall & Oates", 836_974, 14_880, false),
        ("Mumford & Sons", 2_747_016, 2_195, false),
        ("Crosby, Stills, Nash & Young", 1_409_839, 5_944, false),
        ("Unknown & Nobody", 0, 0, false),
    ])
    func decidesWithLastFmListeners(credit: String, full: Int, first: Int, collaboration: Bool) {
        #expect(MainArtist.isCollaboration(fullListeners: full, firstListeners: first) == collaboration)
    }
}
