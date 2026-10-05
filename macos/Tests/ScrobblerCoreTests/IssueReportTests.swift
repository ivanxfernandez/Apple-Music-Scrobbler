import Foundation
import Testing
@testable import ScrobblerCore

@Suite struct IssueReportTests {
    @Test func prefillsTheBugFormFields() throws {
        let url = IssueReport.url(repo: "owner/repo", version: "1.4.0", system: "macOS 15.3", log: "line 1\nline & 2\n")
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.host == "github.com")
        #expect(parts.path == "/owner/repo/issues/new")
        let items = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["template"] == "bug_report.yml")
        #expect(items["version"] == "1.4.0")
        #expect(items["system"] == "macOS 15.3")
        #expect(items["log"] == "line 1\nline & 2")
    }

    @Test func localBuildsReportToTheProjectRepo() {
        #expect(IssueReport.url(repo: "", version: "1", system: "x", log: "").absoluteString
            .hasPrefix("https://github.com/ivanxfernandez/Apple-Music-Scrobbler/issues/new?"))
    }

    @Test func keepsOnlyTheEndOfTheLog() {
        let log = (1...100).map { "line \($0)" }.joined(separator: "\r\n") + "\r\n"
        let tail = IssueReport.logTail(log)
        #expect(tail.hasPrefix("line 71\n"))
        #expect(tail.hasSuffix("line 100"))
        #expect(!tail.contains("\r"))
    }

    @Test func capsTheLogLength() {
        let long = (1...30).map { _ in String(repeating: "x", count: 300) }.joined(separator: "\n")
        let tail = IssueReport.logTail(long)
        #expect(tail.count <= IssueReport.maxLogCharacters)
        #expect(tail.hasPrefix("x"))
        #expect(IssueReport.logTail("") == "")
    }
}
