import Testing
@testable import ScrobblerCore

/// Port of TitleCleanerTests in NameTests.cs. (The Windows "Artist — Album" split isn't needed:
/// Music on the Mac reports artist and album separately.)
@Suite struct TitleCleanerTests {
    @Test(arguments: [
        ("Locomotive (Complicity) [2022 Remaster]", "Locomotive (Complicity)"),
        ("Here Comes the Sun - Remastered 2009", "Here Comes the Sun"),
        ("Bohemian Rhapsody (Remastered 2011)", "Bohemian Rhapsody"),
        ("Paint It Black (2009 Digital Remaster)", "Paint It Black"),
        ("Part 1 - Intro - 2015 Remastered Version", "Part 1 - Intro"),
        // Seen on the Mac (Music app, 2026-10-04)
        ("Pretty Tied Up (The Perils Of Rock N' Roll Decadence) [2022 Remaster]", "Pretty Tied Up (The Perils Of Rock N' Roll Decadence)"),
        ("Disorder (2019 Digital Master)", "Disorder"),
        ("She's Lost Control - 2019 Digital Master", "She's Lost Control"),
        // Left alone
        ("Master of Puppets", "Master of Puppets"),
        ("Master of Puppets (Live)", "Master of Puppets (Live)"),
        ("Smells Like Teen Spirit (Live)", "Smells Like Teen Spirit (Live)"),
        ("Song (feat. Someone)", "Song (feat. Someone)"),
        ("Song - Acoustic", "Song - Acoustic"),
        ("Remastered", "Remastered"),
        ("", ""),
    ])
    func cleansTitles(input: String, expected: String) {
        #expect(TitleCleaner.cleanTitle(input) == expected)
    }

    @Test(arguments: [
        ("Use Your Illusion II (Deluxe Edition)", "Use Your Illusion II"),
        ("Nevermind (20th Anniversary Super Deluxe)", "Nevermind"),
        ("Abbey Road (Remastered)", "Abbey Road"),
        ("Rumours [Expanded Edition]", "Rumours"),
        ("Album (Bonus Track Version)", "Album"),
        ("Espresso - Single", "Espresso"),
        ("Something - EP", "Something"),
        ("Foo (Deluxe Edition) - EP", "Foo"),
        ("Unknown Pleasures (2019 Digital Master)", "Unknown Pleasures"),
        // Left alone
        ("SMITHEREENS", "SMITHEREENS"),
        ("Single", "Single"),
        ("Live at Wembley", "Live at Wembley"),
    ])
    func cleansAlbums(input: String, expected: String) {
        #expect(TitleCleaner.cleanAlbum(input) == expected)
    }

    @Test func applyKeepsEverythingElse() throws {
        let np = NowPlaying(artist: "Guns N' Roses", title: "Locomotive [2022 Remaster]", album: "UYI II (Deluxe Edition)", duration: 522, position: 10, isPlaying: true)
        let cleaned = try #require(TitleCleaner.apply(np))
        #expect(cleaned.artist == "Guns N' Roses")
        #expect(cleaned.title == "Locomotive")
        #expect(cleaned.album == "UYI II")
        #expect(cleaned.duration == 522)
        #expect(cleaned.position == 10)
        #expect(cleaned.isPlaying)
        #expect(TitleCleaner.apply(nil) == nil)
    }
}
