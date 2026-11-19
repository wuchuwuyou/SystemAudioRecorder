import Foundation

// Missing keys or mismatched format arguments make one OS language fail at runtime.
@main
struct LocalizationTests {
    static func main() throws {
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
        let manager = FileManager.default
        let languages = ["en", "zh-Hans"]
        let requiredKeys = ["app.title", "action.record", "action.stop", "action.save", "help.disclosure", "status.noAudio"]
        var tables: [[String: String]] = []
        for language in languages {
            let folder = resources.appendingPathComponent("\(language).lproj")
            let strings = folder.appendingPathComponent("Localizable.strings")
            check(manager.fileExists(atPath: strings.path), "Missing \(language) localization")
            let data = try Data(contentsOf: strings)
            let table = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
            check(table != nil, "Invalid \(language) string table")
            guard let table else { return }
            let bundle = Bundle(path: folder.path)
            check(bundle != nil, "Cannot load \(language) localization bundle")
            for key in requiredKeys {
                let result = bundle?.localizedString(forKey: key, value: "MISSING", table: nil)
                check(result != nil && result != "MISSING" && result != key, "Untranslated \(language) key: \(key)")
            }
            check(table.values.allSatisfy { !$0.isEmpty }, "Empty \(language) translation")
            tables.append(table)
            let privacyData = try Data(contentsOf: folder.appendingPathComponent("InfoPlist.strings"))
            let privacy = try PropertyListSerialization.propertyList(from: privacyData, format: nil) as? [String: String]
            check(privacy?["NSAudioCaptureUsageDescription"]?.isEmpty == false, "Missing privacy disclosure")
        }
        check(Set(tables[0].keys) == Set(tables[1].keys), "Language tables have different keys")
        let format = try NSRegularExpression(pattern: "%[0-9$.*+-]*[@diufsg]")
        for key in tables[0].keys {
            let arguments = tables.map { table -> [String] in
                let value = table[key] ?? ""
                return format.matches(in: value, range: NSRange(value.startIndex..., in: value)).map {
                    (value as NSString).substring(with: $0.range)
                }
            }
            check(arguments[0] == arguments[1], "Format arguments differ for \(key)")
        }
        let infoData = try Data(contentsOf: resources.appendingPathComponent("Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
        let supported = info?["CFBundleLocalizations"] as? [String] ?? []
        check(info?["CFBundleDevelopmentRegion"] as? String == "en", "Missing English development fallback")
        check(Bundle.preferredLocalizations(from: supported, forPreferences: ["zh-CN"]).first == "zh-Hans",
              "Simplified Chinese OS preference is not supported")
        check(Bundle.preferredLocalizations(from: supported, forPreferences: ["en-US"]).first == "en",
              "English OS preference is not supported")
        check(L10n.recordingError("Only silence was captured. Synthetic capture ended.")
              == NSLocalizedString("error.silence", comment: ""), "Silence error did not use localized guidance")
        check(L10n.recordingError("No audio frames were received. Synthetic capture ended.")
              == NSLocalizedString("error.noFrames", comment: ""), "Empty capture did not use localized guidance")
        check(L10n.recordingError("Technical OS error 123") == "Technical OS error 123",
              "Unclassified technical details were lost")
        FileHandle.standardOutput.write(Data("PASS: bilingual strings, format arguments, OS language matching, privacy disclosures, empty/silence error guidance\n".utf8))
    }

    private static func check(_ condition: Bool, _ message: String) {
        guard condition else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
