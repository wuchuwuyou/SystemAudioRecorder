import Darwin
import Foundation

final class RecordingSaveOperation {
    static func save(from source: URL, to destination: URL, replacementConfirmed: Bool) throws -> Error? {
        try RecordingFileStore().save(from: source, to: destination, overwriteExisting: replacementConfirmed)
        do {
            try removeOwnedTemporaryRecording(at: source)
            return nil
        } catch {
            return error
        }
    }

    static func removeOwnedTemporaryRecording(at source: URL) throws {
        let directory = source.deletingLastPathComponent().standardizedFileURL
        let prefix = "SystemAudioRecorder-"
        guard source.isFileURL, source.lastPathComponent == "recording.wav",
              directory.lastPathComponent.hasPrefix(prefix),
              UUID(uuidString: String(directory.lastPathComponent.dropFirst(prefix.count))) != nil,
              directory.deletingLastPathComponent().resolvingSymlinksInPath()
                == FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath() else {
            throw CocoaError(.fileWriteNoPermission)
        }
        var directoryInfo = stat()
        if lstat(directory.path, &directoryInfo) != 0 {
            if errno == ENOENT { return }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard directoryInfo.st_mode & S_IFMT == S_IFDIR,
              directoryInfo.st_uid == geteuid(), directoryInfo.st_mode & 0o777 == 0o700 else {
            throw CocoaError(.fileWriteNoPermission)
        }
        var sourceInfo = stat()
        if lstat(source.path, &sourceInfo) == 0 {
            guard sourceInfo.st_mode & S_IFMT == S_IFREG, sourceInfo.st_uid == geteuid() else {
                throw CocoaError(.fileWriteNoPermission)
            }
            guard unlink(source.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        } else if errno != ENOENT {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        // Never recursively remove a directory: an unrelated or saved file must survive.
        guard rmdir(directory.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}
