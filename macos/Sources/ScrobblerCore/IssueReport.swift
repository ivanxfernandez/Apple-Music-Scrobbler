import Foundation

/// Builds the "Report a Problem" link: a new GitHub issue with the bug form's fields filled in
/// (version, system, recent log lines). The user sees and edits it before submitting.
public enum IssueReport {
    /// The project's repository; local builds without GITHUB_REPO report here too.
    public static let defaultRepo = "ivanxfernandez/Apple-Music-Scrobbler"
    /// GitHub rejects very long URLs, so only the end of the log is included.
    public static let maxLogLines = 30
    public static let maxLogCharacters = 4000

    public static func url(repo: String, version: String, system: String, log: String) -> URL {
        let query = [
            ("template", "bug_report.yml"),
            ("version", version),
            ("system", system),
            ("log", logTail(log)),
        ].map { "\($0.0)=\(Http.escape($0.1))" }.joined(separator: "&")
        return URL(string: "https://github.com/\(repo.isEmpty ? defaultRepo : repo)/issues/new?\(query)")!
    }

    /// The last lines of the log, at most maxLogLines and maxLogCharacters (cut at a line break).
    public static func logTail(_ log: String) -> String {
        // "\r\n" is a single Character in Swift, so normalize line endings before splitting.
        var lines = log.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while lines.last?.isEmpty == true { lines.removeLast() }
        var tail = Array(lines.suffix(maxLogLines))
        while tail.count > 1 && tail.joined(separator: "\n").count > maxLogCharacters { tail.removeFirst() }
        let text = tail.joined(separator: "\n")
        return text.count > maxLogCharacters ? String(text.suffix(maxLogCharacters)) : text
    }
}
