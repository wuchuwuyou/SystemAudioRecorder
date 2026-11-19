import AVFoundation
import Foundation

@main
struct RecordingSaveOperationTests {
    static func main() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent(".build/save-fixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent("saved.wav")
        let source = try makePending(sample: 0.25)
        let sourceDirectory = source.deletingLastPathComponent()
        let initialCleanupError = try RecordingSaveOperation.save(from: source, to: destination, replacementConfirmed: false)
        precondition(initialCleanupError == nil)
        precondition((try? firstSample(at: destination)) == 0.25)
        precondition(!FileManager.default.fileExists(atPath: sourceDirectory.path), "Confirmed Save did not clean its temporary copy")

        let racedDestination = root.appendingPathComponent("raced.wav")
        let retainedSource = try makePending(sample: 0.25)
        let replacementConfirmed = false
        try writeWAV(at: racedDestination, sample: 0.75)
        var refusedRace = false
        do {
            _ = try RecordingSaveOperation.save(from: retainedSource, to: racedDestination,
                                                replacementConfirmed: replacementConfirmed)
        } catch {
            refusedRace = true
        }
        guard refusedRace else {
            FileHandle.standardError.write(Data("FAIL: racing destination was overwritten without explicit Replace authorization\n".utf8))
            exit(1)
        }
        precondition((try? firstSample(at: racedDestination)) == 0.75)
        precondition((try? firstSample(at: retainedSource)) == 0.25, "Failed Save lost pending audio")
        let replaceCleanupError = try RecordingSaveOperation.save(from: retainedSource, to: racedDestination, replacementConfirmed: true)
        precondition(replaceCleanupError == nil)
        precondition((try? firstSample(at: racedDestination)) == 0.25)
        precondition(!FileManager.default.fileExists(atPath: retainedSource.path))

        let failedSource = try makePending(sample: 0.25)
        do {
            _ = try RecordingSaveOperation.save(from: failedSource,
                                                to: root.appendingPathComponent("missing/destination.wav"),
                                                replacementConfirmed: true)
            preconditionFailure("A failed destination write was reported as saved")
        } catch {
            precondition((try? firstSample(at: failedSource)) == 0.25)
        }
        try RecordingSaveOperation.removeOwnedTemporaryRecording(at: failedSource)

        let cleanupSource = try makePending(sample: 0.25)
        let extraFile = cleanupSource.deletingLastPathComponent().appendingPathComponent("keep.txt")
        try "Keep this file".write(to: extraFile, atomically: true, encoding: .utf8)
        let cleanupDestination = root.appendingPathComponent("cleanup-incomplete.wav")
        let cleanupError = try RecordingSaveOperation.save(from: cleanupSource, to: cleanupDestination, replacementConfirmed: false)
        precondition(cleanupError != nil, "Incomplete cleanup was not surfaced independently from Save success")
        precondition((try? firstSample(at: cleanupDestination)) == 0.25)
        precondition(FileManager.default.fileExists(atPath: extraFile.path), "Cleanup recursively removed unrelated contents")
        try FileManager.default.removeItem(at: extraFile)
        try RecordingSaveOperation.removeOwnedTemporaryRecording(at: cleanupSource)

        let emptySource = try makePending(sample: 0)
        try RecordingSaveOperation.removeOwnedTemporaryRecording(at: emptySource)
        precondition(!FileManager.default.fileExists(atPath: emptySource.deletingLastPathComponent().path))

        let unownedSource = root.appendingPathComponent("recording.wav")
        try writeWAV(at: unownedSource, sample: 0.75)
        do {
            try RecordingSaveOperation.removeOwnedTemporaryRecording(at: unownedSource)
            preconditionFailure("Cleanup accepted an unowned directory")
        } catch {
            precondition((try? firstSample(at: unownedSource)) == 0.75)
        }
        let linkedDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SystemAudioRecorder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: root)
        do {
            try RecordingSaveOperation.removeOwnedTemporaryRecording(at: linkedDirectory.appendingPathComponent("recording.wav"))
            preconditionFailure("Cleanup followed a symlink directory")
        } catch {
            precondition((try? firstSample(at: unownedSource)) == 0.75)
        }
        try FileManager.default.removeItem(at: linkedDirectory)
        FileHandle.standardOutput.write(Data("PASS: new Save cleanup, racing destination refusal/retention, explicit Replace, failed Save retention, saved-but-cleanup-incomplete, empty capture cleanup, ownership/symlink refusal\n".utf8))
    }

    static func makePending(sample: Float) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SystemAudioRecorder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("recording.wav")
        try writeWAV(at: url, sample: sample)
        return url
    }

    static func writeWAV(at url: URL, sample: Float) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 128)!
        buffer.frameLength = 128
        for channel in 0..<2 {
            for frame in 0..<128 { buffer.floatChannelData![channel][frame] = sample }
        }
        var settings = format.settings
        settings[AVLinearPCMIsNonInterleaved] = false
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }

    static func firstSample(at url: URL) throws -> Float {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1)!
        try file.read(into: buffer, frameCount: 1)
        precondition(buffer.frameLength == 1)
        return buffer.floatChannelData![0][0]
    }
}
