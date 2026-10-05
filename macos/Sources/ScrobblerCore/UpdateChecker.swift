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
    public let url: URL
}

/// Checks the GitHub repository the app was built from for a newer release.
public enum UpdateChecker {
    private struct GitHubRelease: Decodable {
        let tag_name: String?
        let html_url: String?
        let draft: Bool?
        let prerelease: Bool?
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
              let current = AppVersion(AppInfo.version), isNewer(latest, than: current),
              let url = URL(string: release.html_url ?? "") else { return nil }
        return ReleaseInfo(version: latest, tag: tag, url: url)
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
