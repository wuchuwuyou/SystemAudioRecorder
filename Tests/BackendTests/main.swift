import Foundation

if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--saturated-finalize" {
    signal(SIGPIPE, SIG_IGN)
    let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256)!
    buffer.frameLength = 256
    for channel in 0..<2 {
        for frame in 0..<256 { buffer.floatChannelData![channel][frame] = 0.1 }
    }
    var file: AVAudioFile? = try AVAudioFile(forWriting: URL(fileURLWithPath: CommandLine.arguments[2]), settings: format.settings)
    try file?.write(from: buffer)
    file = nil
    let flags = fcntl(STDERR_FILENO, F_GETFL)
    precondition(fcntl(STDERR_FILENO, F_SETFL, flags | O_NONBLOCK) == 0)
    let fill = [UInt8](repeating: 0, count: 4096)
    while fill.withUnsafeBytes({ Darwin.write(STDERR_FILENO, $0.baseAddress, $0.count) }) > 0 { }
    precondition(errno == EAGAIN)
    precondition(fcntl(STDERR_FILENO, F_SETFL, flags) == 0)
    let telemetry = WaveformTelemetry { _ in
        _ = writeProtocolFrame(Data("WAVEFORM: 0,0,0,0,0,0,0,0\n".utf8), to: STDERR_FILENO)
    }
    telemetry.start()
    telemetry.stop()
    report("STOPPED: requested stop.")
    report("ERROR: Only silence was captured.")
    exit(3)
}

import CoreAudio

let tap = makeSystemAudioTapDescription()
assert(tap.bundleIDs.isEmpty, "System audio must not be restricted to an app.")
assert(tap.processes.isEmpty, "No additional process IDs may be captured.")
assert(tap.isExclusive, "Global capture must include all processes except the exclusion list.")
assert(tap.isPrivate, "The tap must remain private to this recorder.")
assert(tap.muteBehavior == .unmuted, "Computer playback must remain audible.")

import AVFoundation

let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4)!
buffer.frameLength = 4
for channel in 0..<2 {
    for frame in 0..<4 { buffer.floatChannelData![channel][frame] = 0 }
}
assert(!bufferHasSignal(buffer), "Digital silence must be rejected.")
buffer.floatChannelData![1][1] = 0.01
assert(bufferHasSignal(buffer), "Audible PCM samples must be detected.")
buffer.floatChannelData![1][1] = 0.0000001
assert(!bufferHasSignal(buffer), "Samples below the silence threshold must be rejected.")

let interleavedFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                     channels: 2, interleaved: true)!
let interleaved = AVAudioPCMBuffer(pcmFormat: interleavedFormat, frameCapacity: 4)!
interleaved.frameLength = 4
for channel in 0..<2 {
    for frame in 0..<4 { interleaved.floatChannelData![channel][frame * interleaved.stride] = 0 }
}
assert(!bufferHasSignal(interleaved), "Interleaved silence must be rejected.")
interleaved.floatChannelData![1][3 * interleaved.stride] = 0.01
assert(bufferHasSignal(interleaved), "Interleaved audible samples must be detected.")

let envelopeFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
let envelopeBuffer = AVAudioPCMBuffer(pcmFormat: envelopeFormat, frameCapacity: 16)!
envelopeBuffer.frameLength = 16
for channel in 0..<2 {
    for frame in 0..<16 { envelopeBuffer.floatChannelData![channel][frame] = 0 }
}
assert(waveformEnvelope(envelopeBuffer) == Array(repeating: 0, count: 8))
envelopeBuffer.floatChannelData![0][0] = 0.2
envelopeBuffer.floatChannelData![1][1] = -0.5
assert(waveformEnvelope(envelopeBuffer)[0] == 0.5, "Waveform must use real stereo sample peaks.")
envelopeBuffer.floatChannelData![0][8] = 2
assert(waveformEnvelope(envelopeBuffer)[4] == 1, "Visual peaks must be bounded.")
envelopeBuffer.floatChannelData![0][4] = .nan
envelopeBuffer.floatChannelData![1][5] = .infinity
assert(waveformEnvelope(envelopeBuffer)[2] == 0)
let interleavedEnvelope = AVAudioPCMBuffer(pcmFormat: interleavedFormat, frameCapacity: 16)!
interleavedEnvelope.frameLength = 16
for channel in 0..<2 {
    for frame in 0..<16 { interleavedEnvelope.floatChannelData![channel][frame * interleavedEnvelope.stride] = 0 }
}
interleavedEnvelope.floatChannelData![1][3 * interleavedEnvelope.stride] = -0.75
assert(waveformEnvelope(interleavedEnvelope)[1] == 0.75)
interleavedEnvelope.frameLength = 0
assert(waveformEnvelope(interleavedEnvelope) == Array(repeating: 0, count: 8))

let telemetry = WaveformTelemetry { _ in }
telemetry.observe(envelopeBuffer)
assert(telemetry.takeEnvelope()[0] == 0.5)
assert(telemetry.takeEnvelope() == Array(repeating: 0, count: 8), "Silence must not repeat the previous peak.")

let receivedPeak = DispatchSemaphore(value: 0)
let receivedSilence = DispatchSemaphore(value: 0)
let timedTelemetry = WaveformTelemetry { values in
    if values[0] > 0 { receivedPeak.signal() }
    else { receivedSilence.signal() }
}
timedTelemetry.observe(envelopeBuffer)
timedTelemetry.start()
assert(receivedPeak.wait(timeout: .now() + 1) == .success)
assert(receivedSilence.wait(timeout: .now() + 1) == .success, "Idle telemetry must publish silence, not stale peaks.")
timedTelemetry.stop()

signal(SIGPIPE, SIG_IGN)
var saturatedPipe = [Int32](repeating: 0, count: 2)
assert(pipe(&saturatedPipe) == 0)
let pipeFlags = fcntl(saturatedPipe[1], F_GETFL)
assert(fcntl(saturatedPipe[1], F_SETFL, pipeFlags | O_NONBLOCK) == 0)
let fill = [UInt8](repeating: 0, count: 4096)
while fill.withUnsafeBytes({ Darwin.write(saturatedPipe[1], $0.baseAddress, $0.count) }) > 0 { }
assert(errno == EAGAIN)
assert(fcntl(saturatedPipe[1], F_SETFL, pipeFlags) == 0)
let pipeStopped = DispatchSemaphore(value: 0)
let blockedTelemetry = WaveformTelemetry { _ in
    _ = writeProtocolFrame(Data("WAVEFORM: 0,0,0,0,0,0,0,0\n".utf8), to: saturatedPipe[1])
}
blockedTelemetry.start()
Thread.sleep(forTimeInterval: 0.1)
DispatchQueue.global().async { blockedTelemetry.stop(); pipeStopped.signal() }
let stoppedPromptly = pipeStopped.wait(timeout: .now() + 0.3) == .success
Darwin.close(saturatedPipe[0])
if !stoppedPromptly {
    _ = pipeStopped.wait(timeout: .now() + 1)
    FileHandle.standardError.write(Data("FAIL: saturated waveform pipe blocked telemetry shutdown\n".utf8))
    Darwin.close(saturatedPipe[1])
    exit(1)
}
Darwin.close(saturatedPipe[1])

let finalizationOutput = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(".build/finalization-\(UUID().uuidString).wav")
try FileManager.default.createDirectory(at: finalizationOutput.deletingLastPathComponent(), withIntermediateDirectories: true)
let finalizationProcess = Process()
let finalizationErrors = Pipe()
let finalizationExited = DispatchSemaphore(value: 0)
finalizationProcess.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
finalizationProcess.arguments = ["--saturated-finalize", finalizationOutput.path]
finalizationProcess.standardError = finalizationErrors
finalizationProcess.terminationHandler = { _ in finalizationExited.signal() }
try finalizationProcess.run()
let finalizedPromptly = finalizationExited.wait(timeout: .now() + 1) == .success
if !finalizedPromptly {
    finalizationProcess.terminate()
    finalizationProcess.waitUntilExit()
    FileHandle.standardError.write(Data("FAIL: terminal diagnostics blocked helper exit after WAV finalization\n".utf8))
    exit(1)
}
assert(finalizationProcess.terminationStatus == 3)
let finalizedFile = try AVAudioFile(forReading: finalizationOutput)
assert(finalizedFile.length == 256, "Backpressure must not corrupt the finalized WAV.")
FileHandle.standardOutput.write(Data("PASS: saturated telemetry, WAV finalization, terminal reporting, and helper exit\n".utf8))
