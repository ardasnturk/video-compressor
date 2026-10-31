import XCTest

/// Every string in the catalog must be translated into every supported language,
/// with the same format specifiers as the English key.
final class LocalizationTests: XCTestCase {
    static let languages = ["tr", "de", "fr", "es", "ja", "zh-Hans"]

    private var catalog: [String: Any] {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Resources/Localizable.xcstrings")
            let data = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            return json["strings"] as! [String: Any]
        }
    }

    private func specifiers(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "%(?:\\d\\$)?(lld|ld|d|@|f|lf)")
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map {
            String(text[Range($0.range(at: 1), in: text)!])
        }.sorted()
    }

    /// All translated values for a localization entry (plain or plural variations).
    private func values(_ localization: [String: Any]) -> [String] {
        if let unit = localization["stringUnit"] as? [String: Any], unit["state"] as? String == "translated" {
            return [unit["value"] as! String]
        }
        if let variations = localization["variations"] as? [String: Any],
           let plural = variations["plural"] as? [String: [String: Any]], plural["other"] != nil {
            return plural.values.compactMap { ($0["stringUnit"] as? [String: Any])?["value"] as? String }
        }
        return []
    }

    func testCatalogIsComplete() throws {
        let strings = try catalog
        XCTAssertGreaterThan(strings.count, 100)
        for (key, entry) in strings {
            let entry = entry as! [String: Any]
            if entry["extractionState"] as? String == "stale" {
                XCTFail("Stale key, run scripts/update-strings.sh and remove it: \(key)")
            }
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            for language in Self.languages {
                guard let localization = localizations[language] else {
                    XCTFail("Missing \(language) translation for \"\(key)\""); continue
                }
                let translated = values(localization)
                XCTAssertFalse(translated.isEmpty, "Untranslated \(language): \"\(key)\"")
                for value in translated {
                    XCTAssertEqual(specifiers(value), specifiers(key),
                                   "Format specifiers differ in \(language) for \"\(key)\": \(value)")
                }
            }
        }
    }
}
