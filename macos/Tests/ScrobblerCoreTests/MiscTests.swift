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

@Suite struct ReleaseAssetTests {
    static let hash = "efada22d5208773242970c1cf89a1cef708115a6dd118b7184f825ad13ddd993"

    @Test func readsGitHubDigests() {
        #expect(UpdateChecker.sha256(fromDigest: "sha256:" + Self.hash.uppercased()) == Self.hash)
        #expect(UpdateChecker.sha256(fromDigest: "sha256:abc") == nil)
        #expect(UpdateChecker.sha256(fromDigest: "md5:" + Self.hash) == nil)
        #expect(UpdateChecker.sha256(fromDigest: nil) == nil)
    }

    @Test func picksTheMacZipWithItsDigest() throws {
        let json = """
        {"tag_name":"v1.3.0","html_url":"https://github.com/o/r/releases/tag/v1.3.0","assets":[
          {"name":"AppleMusicScrobbler.exe","browser_download_url":"https://github.com/o/r/releases/download/v1.3.0/AppleMusicScrobbler.exe","digest":"sha256:\(String(repeating: "a", count: 64))"},
          {"name":"AppleMusicScrobbler-macOS.zip","browser_download_url":"https://github.com/o/r/releases/download/v1.3.0/AppleMusicScrobbler-macOS.zip","digest":"sha256:\(Self.hash)"}]}
        """
        let release = try JSONDecoder().decode(UpdateChecker.GitHubRelease.self, from: Data(json.utf8))
        let asset = try #require(UpdateChecker.asset(named: UpdateChecker.macAssetName, in: release.assets))
        #expect(asset.url.lastPathComponent == "AppleMusicScrobbler-macOS.zip")
        #expect(asset.sha256 == Self.hash)
    }

    @Test func ignoresAssetsWithoutADigest() throws {
        let json = #"{"assets":[{"name":"AppleMusicScrobbler-macOS.zip","browser_download_url":"https://x/y.zip"}]}"#
        let release = try JSONDecoder().decode(UpdateChecker.GitHubRelease.self, from: Data(json.utf8))
        #expect(UpdateChecker.asset(named: UpdateChecker.macAssetName, in: release.assets) == nil)
        #expect(UpdateChecker.asset(named: UpdateChecker.macAssetName, in: nil) == nil)
    }
}

@Suite struct AppLocationTests {
    @Test func knowsTheApplicationsFolders() {
        #expect(AppLocation.isInApplications("/Applications/Apple Music Scrobbler.app", home: "/Users/ivan"))
        #expect(AppLocation.isInApplications("/Users/ivan/Applications/Apple Music Scrobbler.app", home: "/Users/ivan"))
        #expect(!AppLocation.isInApplications("/Users/ivan/Downloads/Apple Music Scrobbler.app", home: "/Users/ivan"))
        #expect(!AppLocation.isInApplications("/Applications Old/Apple Music Scrobbler.app", home: "/Users/ivan"))
    }

    @Test func recognizesTranslocatedCopies() {
        #expect(AppLocation.isTranslocated("/private/var/folders/xk/abc/T/AppTranslocation/1234-5678/d/Apple Music Scrobbler.app"))
        #expect(!AppLocation.isTranslocated("/Applications/Apple Music Scrobbler.app"))
    }
}
