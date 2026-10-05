import CryptoKit
import Foundation
import Testing
@testable import ScrobblerCore

/// Port of MiscTests.cs.
@Suite struct UpdateCheckerTests {
    @Test(arguments: [
        ("v1.2.0", AppVersion(1, 2, 0)),
        ("1.2", AppVersion(1, 2, 0)),
        ("V2", AppVersion(2, 0, 0)),
        ("v1.2.0-beta.1", AppVersion(1, 2, 0)),
        ("v1.2.3+build.7", AppVersion(1, 2, 3)),
    ])
    func parsesReleaseTags(tag: String, expected: AppVersion) {
        #expect(UpdateChecker.parseVersion(tag) == expected)
    }

    @Test(arguments: ["", "nightly", "v", "1.x", "1..2"])
    func rejectsNonVersionTags(tag: String) {
        #expect(UpdateChecker.parseVersion(tag) == nil)
    }

    @Test func rejectsNil() {
        #expect(UpdateChecker.parseVersion(nil) == nil)
    }

    @Test(arguments: [
        ("1.2.0", "1.1.9.0", true),
        ("1.10.0", "1.9.0.0", true),
        ("1.2", "1.2.0.0", false),
        ("1.1.0", "1.2.0.0", false),
    ])
    func comparesVersions(candidate: String, current: String, newer: Bool) throws {
        let a = try #require(AppVersion(candidate)), b = try #require(AppVersion(current))
        #expect(UpdateChecker.isNewer(a, than: b) == newer)
    }
}

@Suite struct LastFmSignatureTests {
    static func md5(_ s: String) -> String {
        Insecure.MD5.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    @Test func signsParametersSortedByNameThenSecret() {
        let parameters = [
            "track[0]": "Song",
            "method": "track.scrobble",
            "artist[0]": "Artist",
            "api_key": "KEY",
            "sk": "SESSION",
            "album[0]": "Album",
        ]
        let expected = Self.md5("album[0]Album" + "api_keyKEY" + "artist[0]Artist" + "methodtrack.scrobble" + "skSESSION" + "track[0]Song" + "SECRET")
        #expect(LastFmClient.sign(parameters, secret: "SECRET") == expected)
    }

    @Test func signsNonAsciiAsUtf8() {
        let parameters = ["artist": "Молчат Дома", "track": "Судно"]
        #expect(LastFmClient.sign(parameters, secret: "S") == Self.md5("artistМолчат ДомаtrackСудноS"))
    }

    @Test func matchesKnownMd5() {
        // md5("abc") is a standard test vector
        #expect(LastFmClient.sign([:], secret: "abc") == "900150983cd24fb0d6963f7d28e17f72")
    }

    @Test func formEncodingKeepsOnlyUnreservedCharacters() {
        #expect(Http.escape("AC/DC & Queen = 100% ñ") == "AC%2FDC%20%26%20Queen%20%3D%20100%25%20%C3%B1")
        #expect(Http.escape("a-b_c.d~e") == "a-b_c.d~e")
    }
}
