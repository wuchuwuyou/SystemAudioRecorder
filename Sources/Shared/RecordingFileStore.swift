import AVFoundation
import Foundation

final class RecordingFileStore {
    func isUsableRecording(at url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "wav",
              let audio = try? AVAudioFile(forReading: url) else { return false }
        return audio.length > 0
    }

    func save(from source: URL, to destination: URL, overwriteExisting: Bool) throws {
        let manager = FileManager.default
        guard isUsableRecording(at: source) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard source.standardizedFileURL.resolvingSymlinksInPath() != destination.standardizedFileURL.resolvingSymlinksInPath() else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        if manager.fileExists(atPath: destination.path), !overwriteExisting {
            throw CocoaError(.fileWriteFileExists)
        }
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".system-audio-" + UUID().uuidString + ".wav")
        defer { if manager.fileExists(atPath: staging.path) { try? manager.removeItem(at: staging) } }
        try manager.copyItem(at: source, to: staging)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
        let sourceSize = try manager.attributesOfItem(atPath: source.path)[.size] as? NSNumber
        let stagedSize = try manager.attributesOfItem(atPath: staging.path)[.size] as? NSNumber
        guard sourceSize == stagedSize, isUsableRecording(at: staging) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if overwriteExisting, manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: staging,
                                          backupItemName: nil, options: .usingNewMetadataOnly)
        } else {
            try manager.moveItem(at: staging, to: destination)
        }
    }
}
