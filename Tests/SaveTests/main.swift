import AVFoundation
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("build/save-fixtures-" + UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
let source = root.appendingPathComponent("recording.wav")
let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000,
    AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
    AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
var writer: AVAudioFile? = try AVAudioFile(forWriting: source, settings: settings,
                                         commonFormat: .pcmFormatFloat32, interleaved: false)
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48)!
buffer.frameLength = 48
for channel in 0..<2 {
    for frame in 0..<48 { buffer.floatChannelData![channel][frame] = 0.01 }
}
try writer!.write(from: buffer)
writer = nil
let original = try Data(contentsOf: source)
let store = RecordingFileStore()
assert(store.isUsableRecording(at: source), "A real PCM WAV must be recognized.")
let destination = root.appendingPathComponent("saved.wav")
try store.save(from: source, to: destination, overwriteExisting: false)
let saved = try Data(contentsOf: destination)
assert(saved == original)
let retainedSource = try Data(contentsOf: source)
assert(retainedSource == original, "The source must survive saving.")
let permissions = try FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions] as? NSNumber
assert(permissions?.intValue == 0o600)
let old = Data("Existing destination must be preserved".utf8)
let existing = root.appendingPathComponent("existing.wav")
try old.write(to: existing)
var refused = false
 do { try store.save(from: source, to: existing, overwriteExisting: false) }
 catch { refused = true }
let protectedDestination = try Data(contentsOf: existing)
assert(refused && protectedDestination == old)
try store.save(from: source, to: existing, overwriteExisting: true)
let replaced = try Data(contentsOf: existing)
assert(replaced == original)
let replacedPermissions = try FileManager.default.attributesOfItem(atPath: existing.path)[.posixPermissions] as? NSNumber
assert(replacedPermissions?.intValue == 0o600)
let invalid = root.appendingPathComponent("invalid.wav")
try Data("Not audio".utf8).write(to: invalid)
var rejected = false
 do { try store.save(from: invalid, to: existing, overwriteExisting: true) }
 catch { rejected = true }
let unchangedDestination = try Data(contentsOf: existing)
assert(rejected && unchangedDestination == original)
var failed = false
 do { try store.save(from: source, to: root.appendingPathComponent("missing/record.wav"), overwriteExisting: false) }
 catch { failed = true }
let recoverableSource = try Data(contentsOf: source)
assert(failed && recoverableSource == original)
assert(!store.isUsableRecording(at: invalid))
let empty = root.appendingPathComponent("empty.wav")
var emptyWriter: AVAudioFile? = try AVAudioFile(forWriting: empty, settings: settings,
                                              commonFormat: .pcmFormatFloat32, interleaved: false)
emptyWriter = nil
assert(!store.isUsableRecording(at: empty), "A WAV header without frames is not a recording.")
var samePathRejected = false
do { try store.save(from: source, to: source, overwriteExisting: true) }
catch { samePathRejected = true }
let preservedOriginal = try Data(contentsOf: source)
assert(samePathRejected && preservedOriginal == original)
FileHandle.standardOutput.write(Data("Atomic save behavior tests passed.\n".utf8))
