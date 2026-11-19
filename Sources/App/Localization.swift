import Foundation

// Bundle localization follows the OS; the recording protocol stays English.
enum L10n {
    static func string(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: arguments)
    }

    static func recordingError(_ detail: String) -> String {
        if detail.contains("Only silence was captured") {
            return string("error.silence")
        }
        if detail.contains("No audio frames were received") {
            return string("error.noFrames")
        }
        return detail
    }
}
