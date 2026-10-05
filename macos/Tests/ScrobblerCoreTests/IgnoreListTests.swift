import Testing
@testable import ScrobblerCore

@Suite struct IgnoreListTests {
    @Test func matchesIgnoringCaseAccentsAndPunctuation() {
        let list = ["José José", "AC/DC"]
        #expect(IgnoreList.isIgnored("jose jose", in: list))
        #expect(IgnoreList.isIgnored("AC-DC", in: list))
        #expect(!IgnoreList.isIgnored("Joji", in: list))
        #expect(!IgnoreList.isIgnored("Joji", in: []))
    }

    @Test func coversCollaborationsOfAnIgnoredArtist() {
        #expect(IgnoreList.isIgnored("Joji & BENEE", in: ["Joji"]))
        #expect(IgnoreList.isIgnored("Joji & BENEE", in: ["joji & benee"]))
        // Only the first artist counts, so ignoring a guest doesn't hide the main artist's songs.
        #expect(!IgnoreList.isIgnored("Joji & BENEE", in: ["BENEE"]))
    }

    @Test func addsOnceAndKeepsTheListSorted() {
        var list = IgnoreList.adding("Zoé", to: [])
        list = IgnoreList.adding("bôa", to: list)
        list = IgnoreList.adding("ZOE", to: list)
        list = IgnoreList.adding("  ", to: list)
        #expect(list == ["bôa", "Zoé"])
        #expect(IgnoreList.removing("zoe", from: list) == ["bôa"])
    }
}
