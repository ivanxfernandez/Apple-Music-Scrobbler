import Foundation

/// A version number like 1.2.0. Compared as major, minor, patch (a 4th part is ignored, so 1.2 == 1.2.0 == 1.2.0.0).
public struct AppVersion: Comparable, CustomStringConvertible {
    public let major: Int, minor: Int, patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// "1.2", "1.2.0" or "1.2.0.0"; nil for anything else.
    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber), let n = Int(part) else { return nil }
            numbers.append(n)
        }
        self.init(numbers[0], numbers[1], numbers.count > 2 ? numbers[2] : 0)
    }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}

public struct ReleaseInfo {
    public let version: AppVersion
    public let tag: String
    /// The release page.
    public let url: URL
    /// This platform's download, if the release has one with a SHA-256 to check it against.
    public let download: ReleaseAsset?

    public init(version: AppVersion, tag: String, url: URL, download: ReleaseAsset?) {
        self.version = version
        self.tag = tag
        self.url = url
        self.download = download
    }
}

public struct ReleaseAsset: Equatable {
    public let name: String
    public let url: URL
    /// Lowercase hex SHA-256 from GitHub's asset digest.
    public let sha256: String
}

/// Checks the GitHub repository the app was built from for a newer release.
public enum UpdateChecker {
    /// The Mac app's file in each release (see build-app.sh and release.yml).
    public static let macAssetName = "AppleMusicScrobbler-macOS.zip"

    /// For --pretend-version: check for updates as if this were an older version (to test the updater).
    nonisolated(unsafe) public static var pretendVersion: String?

    struct GitHubAsset: Decodable {
        let name: String?
        let browser_download_url: String?
        let digest: String?
    }

    struct GitHubRelease: Decodable {
        let tag_name: String?
        let html_url: String?
        let draft: Bool?
        let prerelease: Bool?
        let assets: [GitHubAsset]?
    }

    /// The latest release if it's newer than this app; nil otherwise or when the app isn't a release build.
    public static func newerRelease() async throws -> ReleaseInfo? {
        if AppInfo.gitHubRepo.isEmpty { return nil }

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(AppInfo.gitHubRepo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (body, response) = try await Http.session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil } // 404 = no releases yet
        let release = try JSONDecoder().decode(GitHubRelease.self, from: body)

        guard release.draft != true, release.prerelease != true,
              let tag = release.tag_name, let latest = parseVersion(tag),
              let current = AppVersion(pretendVersion ?? AppInfo.version), isNewer(latest, than: current),
              let url = URL(string: release.html_url ?? "") else { return nil }
        return ReleaseInfo(version: latest, tag: tag, url: url, download: asset(named: macAssetName, in: release.assets))
    }

    /// The named file of a release, if it has a download URL and a SHA-256 digest.
    static func asset(named name: String, in assets: [GitHubAsset]?) -> ReleaseAsset? {
        guard let a = assets?.first(where: { $0.name == name }),
              let url = URL(string: a.browser_download_url ?? ""), url.scheme == "https",
              let sha256 = sha256(fromDigest: a.digest) else { return nil }
        return ReleaseAsset(name: name, url: url, sha256: sha256)
    }

    /// "sha256:ABC…" → "abc…"; nil for anything else.
    public static func sha256(fromDigest digest: String?) -> String? {
        guard let digest, digest.lowercased().hasPrefix("sha256:") else { return nil }
        let hex = digest.dropFirst("sha256:".count).lowercased()
        return hex.count == 64 && hex.allSatisfy(\.isHexDigit) ? String(hex) : nil
    }

    /// Parses tags like "v1.2.0", "1.2", "V2" or "v1.2.0-beta.1" (suffix ignored).
    public static func parseVersion(_ tag: String?) -> AppVersion? {
        guard var s = tag?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        while s.first == "v" || s.first == "V" { s.removeFirst() }
        if let cut = s.firstIndex(where: { $0 == "-" || $0 == "+" }) { s = String(s[..<cut]) }
        return AppVersion(s.contains(".") ? s : s + ".0")
    }

    public static func isNewer(_ candidate: AppVersion, than current: AppVersion) -> Bool { candidate > current }
}
