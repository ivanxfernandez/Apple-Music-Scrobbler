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

@Suite struct RecentScrobblesTests {
    static func item(_ i: Int) -> RecentScrobble { RecentScrobble(timestamp: Int64(i), artist: "A", track: "T\(i)") }

    @Test func keepsTheNewestTenNewestFirst() {
        var list: [RecentScrobble] = []
        for i in 1...12 { list = RecentScrobbles.adding(Self.item(i), to: list) }
        #expect(list.count == 10)
        #expect(list.first?.track == "T12")
        #expect(list.last?.track == "T3")
    }

    @Test func showsTheTimeTodayAndTheDateBefore() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let locale = Locale(identifier: "en_US")
        func at(_ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)))
        }
        let now = try at(4, 23, 20)
        let today = RecentScrobble(timestamp: Int64(try at(4, 22, 5).timeIntervalSince1970), artist: "A", track: "T")
        let earlier = RecentScrobble(timestamp: Int64(try at(2, 9, 30).timeIntervalSince1970), artist: "A", track: "T")
        let todayText = RecentScrobbles.time(today, now: now, calendar: calendar, locale: locale)
        let earlierText = RecentScrobbles.time(earlier, now: now, calendar: calendar, locale: locale)
        #expect(todayText.hasPrefix("10:05") && todayText.hasSuffix("PM") && !todayText.contains("Oct"))
        #expect(earlierText.hasPrefix("Oct 2") && earlierText.contains("9:30"))
    }

    @Test func linksToTheSongOnLastFm() {
        let item = RecentScrobble(timestamp: 0, artist: "AC/DC", track: "T.N.T.")
        #expect(item.url?.absoluteString == "https://www.last.fm/music/AC%2FDC/_/T.N.T.")
    }
}
