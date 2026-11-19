import AVFoundation
import CoreAudio
import Foundation

func requireSuccess(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else {
        throw CaptureError(errorDescription: "\(operation) failed (OSStatus \(status)).")
    }
}

final class AudioSink {
    let format: AVAudioFormat
    private var file: AVAudioFile?
    private let onFailure: () -> Void
    private let onBuffer: (AVAudioPCMBuffer) -> Void
    private(set) var failure: Error?
    private(set) var frames: AVAudioFramePosition = 0
    private(set) var hasSignal = false

    init(url: URL, format: AVAudioFormat, onFailure: @escaping () -> Void, onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        self.format = format
        self.onFailure = onFailure
        self.onBuffer = onBuffer
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw CaptureError(errorDescription: "Cannot reserve the output file without overwriting: \(errno).")
        }
        Darwin.close(descriptor)
        file = try AVAudioFile(forWriting: url, settings: format.settings,
                               commonFormat: format.commonFormat, interleaved: format.isInterleaved)
    }

    func append(_ input: UnsafePointer<AudioBufferList>) {
        guard failure == nil, let file,
              input.pointee.mNumberBuffers > 0, input.pointee.mBuffers.mDataByteSize > 0 else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil) else {
            failure = CaptureError(errorDescription: "Cannot interpret the captured audio buffer.")
            onFailure()
            return
        }
        do {
            try file.write(from: buffer)
            if !hasSignal { hasSignal = bufferHasSignal(buffer) }
            frames += AVAudioFramePosition(buffer.frameLength)
            onBuffer(buffer)
        } catch {
            failure = error
            onFailure()
        }
    }

    func close() {
        file = nil
    }
}

func capture() throws {
    signal(SIGPIPE, SIG_IGN)
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 1 else {
        throw CaptureError(errorDescription: "Usage: recorder --check | --prepare | /absolute/path.wav")
    }
    let argument = arguments[0]
    let preparationOnly = argument == "--prepare"
    let output: URL?
    if argument == "--check" || preparationOnly {
        output = nil
    } else {
        guard argument.hasPrefix("/"), argument.lowercased().hasSuffix(".wav") else {
            throw CaptureError(errorDescription: "The output must be an absolute WAV path.")
        }
        guard !FileManager.default.fileExists(atPath: argument) else {
            throw CaptureError(errorDescription: "Refusing to overwrite an existing file.")
        }
        output = URL(fileURLWithPath: argument)
    }
    let description = makeSystemAudioTapDescription()
    guard description.bundleIDs.isEmpty, description.processes.isEmpty,
          description.isExclusive, description.isPrivate else {
        throw CaptureError(errorDescription: "Capture scope is not configured as private system-output audio.")
    }
    if argument == "--check" {
        report("CHECK_OK: System-output-only capture; no microphone; all playback applications included.")
        return
    }

    report("Preparing a system-output audio tap. A macOS system-audio permission prompt may appear.")
    var tapID = AudioObjectID(kAudioObjectUnknown)
    try requireSuccess(AudioHardwareCreateProcessTap(description, &tapID), "Create process tap")
    defer { AudioHardwareDestroyProcessTap(tapID) }
    var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                             mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    var stream = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    try requireSuccess(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &stream), "Read tap format")
    guard let format = AVAudioFormat(streamDescription: &stream), format.channelCount > 0,
          format.sampleRate > 0, format.commonFormat == .pcmFormatFloat32 else {
        throw CaptureError(errorDescription: "The audio tap did not provide a supported Float32 PCM format.")
    }
    report("Tap format: \(format.sampleRate) Hz, \(format.channelCount) channels.")
    if preparationOnly {
        report("PREPARE_OK: No recording or output file was created. Audible capture remains unverified.")
        return
    }
    guard let output else { return }

    let properties: [String: Any] = [
        kAudioAggregateDeviceNameKey: "System Audio Recorder",
        kAudioAggregateDeviceUIDKey: UUID().uuidString,
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceTapAutoStartKey: true,
        kAudioAggregateDeviceTapListKey: [[
            kAudioSubTapUIDKey: description.uuid.uuidString,
            kAudioSubTapDriftCompensationKey: true
        ]]
    ]
    var deviceID = AudioObjectID(kAudioObjectUnknown)
    try requireSuccess(AudioHardwareCreateAggregateDevice(properties as CFDictionary, &deviceID), "Create private capture device")
    defer { AudioHardwareDestroyAggregateDevice(deviceID) }
    let queue = DispatchQueue(label: "local.system-audio.writer")
    let stop = DispatchSemaphore(value: 0)
    let telemetry = WaveformTelemetry { values in
        let samples = values.map { String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), $0) }.joined(separator: ",")
        if writeProtocolFrame(Data(("WAVEFORM: " + samples + "\n").utf8), to: STDERR_FILENO) == .closed {
            stop.signal()
        }
    }
    let sink = try AudioSink(url: output, format: format, onFailure: { stop.signal() }, onBuffer: { telemetry.observe($0) })
    defer { queue.sync { sink.close() } }
    var callback: AudioDeviceIOProcID?
    try requireSuccess(AudioDeviceCreateIOProcIDWithBlock(&callback, deviceID, queue) {
        _, input, _, _, _ in sink.append(input)
    }, "Create audio writer")
    guard let callback else {
        throw CaptureError(errorDescription: "The audio callback was not created.")
    }
    defer { AudioDeviceDestroyIOProcID(deviceID, callback) }
    try requireSuccess(AudioDeviceStart(deviceID, callback), "Start capture")
    var deviceStarted = true
    defer { if deviceStarted { AudioDeviceStop(deviceID, callback) } }

    report("RECORDING: All computer playback is being recorded. Press Return to stop.")
    telemetry.start()
    defer { telemetry.stop() }
    DispatchQueue.global().async {
        _ = readLine()
        stop.signal()
    }
    stop.wait()
    try requireSuccess(AudioDeviceStop(deviceID, callback), "Stop capture")
    deviceStarted = false
    telemetry.stop()
    let summary = queue.sync { () -> (AVAudioFramePosition, Bool, Error?) in
        sink.close()
        return (sink.frames, sink.hasSignal, sink.failure)
    }
    if let failure = summary.2 { throw failure }
    guard summary.0 > 0 else {
        throw CaptureError(errorDescription: "No audio frames were received. The output must not be treated as a successful recording.", exitCode: 2)
    }
    guard summary.1 else {
        throw CaptureError(errorDescription: "Only silence was captured. Do not treat the output as a successful voice recording.", exitCode: 3)
    }
    report("STOPPED: requested stop.")
    report("Saved \(Double(summary.0) / format.sampleRate) seconds of non-silent PCM audio.")
}

do {
    try capture()
} catch {
    report("ERROR: \(error.localizedDescription)")
    exit((error as? CaptureError)?.exitCode ?? 1)
}
