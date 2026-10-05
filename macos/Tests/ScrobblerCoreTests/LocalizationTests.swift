import Foundation
import Testing
@testable import ScrobblerCore

@Suite(.serialized) struct LocalizationTests {
    /// Every L("…") in the app's code, with Swift escapes (\u{…}, \n, \") turned into the real characters.
    static func keysUsedInCode() throws -> Set<String> {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" && $0.lastPathComponent != "Localization.swift" } ?? []
        let pattern = try NSRegularExpression(pattern: #"\bL\("((?:[^"\\]|\\.)*)""#)
        var keys = Set<String>()
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                keys.insert(unescape(String(text[Range(match.range(at: 1), in: text)!])))
            }
        }
        return keys
    }

    static func unescape(_ literal: String) -> String {
        var result = ""
        var chars = literal.makeIterator()
        while let c = chars.next() {
            guard c == "\\", let next = chars.next() else { result.append(c); continue }
            switch next {
            case "n": result.append("\n")
            case "t": result.append("\t")
            case "u":
                _ = chars.next() // {
                var hex = ""
                while let h = chars.next(), h != "}" { hex.append(h) }
                if let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) { result.unicodeScalars.append(scalar) }
            default: result.append(next) // \" \\ \'
            }
        }
        return result
    }

    static func placeholders(_ s: String) -> Int { s.components(separatedBy: "%@").count - 1 }

    @Test func everyTextInTheAppHasASpanishTranslation() throws {
        let keys = try Self.keysUsedInCode()
        #expect(keys.count > 80)
        let missing = keys.filter { Localization.spanish[$0] == nil }.sorted()
        #expect(missing.isEmpty, "Missing Spanish for: \(missing)")
    }

    @Test func translationsKeepThePlaceholders() {
        for (english, spanish) in Localization.spanish {
            #expect(Self.placeholders(english) == Self.placeholders(spanish), "\(english)")
        }
    }

    @Test func noUnusedTranslations() throws {
        let keys = try Self.keysUsedInCode()
        let unused = Localization.spanish.keys.filter { !keys.contains($0) }.sorted()
        #expect(unused.isEmpty, "Not used in the code: \(unused)")
    }

    @Test func picksTheLanguageFromThePreferredList() {
        #expect(Localization.detect(["es-MX", "en-US"]) == "es")
        #expect(Localization.detect(["en-US", "es-MX"]) == "en")
        #expect(Localization.detect(["fr-FR", "es-ES"]) == "es") // first language with a translation
        #expect(Localization.detect(["fr-FR"]) == "en")
        #expect(Localization.detect([]) == "en")
    }

    @Test func fillsPlaceholdersInOrder() {
        let saved = Localization.language
        defer { Localization.language = saved }
        Localization.language = "es"
        #expect(L("Update to %@ %@?", "Apple Music Scrobbler", "v1.5.0") == "¿Actualizar a Apple Music Scrobbler v1.5.0?")
        #expect(L("Not in any table") == "Not in any table")
        Localization.language = "en"
        #expect(L("%@ Waiting to Send", 3) == "3 Waiting to Send")
    }
}
