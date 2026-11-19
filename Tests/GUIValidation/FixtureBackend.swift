import AVFoundation
import Foundation

@main
struct FixtureBackend {
    static func main() throws {
        // Only synthetic PCM is generated; no capture or microphone device is opened.
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
        var file: AVAudioFile? = try AVAudioFile(forWriting: output, settings: settings,
                                               commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
        buffer.frameLength = 48_000
        for channel in 0..<2 {
            for frame in 0..<48_000 {
                let position = Double(frame) / 48_000
                let envelope = 0.12 + 0.1 * sin(position * 2 * .pi)
                buffer.floatChannelData![channel][frame] = Float(envelope * sin(position * 440 * 2 * .pi))
            }
        }
        let fixtureQueue = DispatchQueue(label: "synthetic.waveform.fixture")
        let timer = DispatchSource.makeTimerSource(queue: fixtureQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(50))
        timer.setEventHandler {
            let values = waveformEnvelope(buffer).map { String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), $0) }.joined(separator: ",")
            try? FileHandle.standardError.write(contentsOf: Data(("WAVEFORM: " + values + "\n").utf8))
        }
        FileHandle.standardError.write(Data("RECORDING: synthetic fixture only\n".utf8))
        timer.resume()
        _ = readLine()
        timer.cancel()
        fixtureQueue.sync { }
        try file!.write(from: buffer)
        file = nil
        let validated = try AVAudioFile(forReading: output)
        assert(validated.length == 48_000)
    }
}
