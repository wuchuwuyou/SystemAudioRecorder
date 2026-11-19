import AVFoundation
import Foundation

func waveformEnvelope(_ buffer: AVAudioPCMBuffer) -> [Float] {
    var points = Array(repeating: Float(0), count: 8)
    guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return points }
    let frames = Int(buffer.frameLength)
    for index in points.indices {
        let lower = frames * index / points.count
        let upper = frames * (index + 1) / points.count
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in lower..<upper {
                let sample = channels[channel][frame * buffer.stride]
                if sample.isFinite { points[index] = max(points[index], min(abs(sample), 1)) }
            }
        }
    }
    return points
}

final class WaveformTelemetry {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "local.system-audio.waveform")
    private var pending = Array(repeating: Float(0), count: 8)
    private var timer: DispatchSourceTimer?
    private let emit: ([Float]) -> Void

    init(emit: @escaping ([Float]) -> Void) {
        self.emit = emit
    }

    func observe(_ buffer: AVAudioPCMBuffer) {
        let values = waveformEnvelope(buffer)
        lock.lock()
        for index in pending.indices { pending[index] = max(pending[index], values[index]) }
        lock.unlock()
    }

    func takeEnvelope() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let values = pending
        pending = Array(repeating: 0, count: 8)
        return values
    }

    func start() {
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: .milliseconds(50), leeway: .milliseconds(5))
        source.setEventHandler { [weak self] in
            guard let this = self else { return }
            this.emit(this.takeEnvelope())
        }
        timer = source
        source.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        queue.sync { }
    }
}

enum ProtocolWriteResult: Equatable {
    case written, dropped, closed
}

func writeProtocolFrame(_ data: Data, to descriptor: Int32) -> ProtocolWriteResult {
    guard !data.isEmpty, data.count <= PIPE_BUF else { return .dropped }
    let flags = fcntl(descriptor, F_GETFL)
    guard flags >= 0 else { return .closed }
    guard fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else { return .dropped }
    // Drop congested diagnostics instead of blocking capture shutdown.
    defer { _ = fcntl(descriptor, F_SETFL, flags) }
    let count = data.withUnsafeBytes { bytes in
        Darwin.write(descriptor, bytes.baseAddress, bytes.count)
    }
    if count == data.count { return .written }
    if count < 0, errno == EPIPE || errno == EBADF { return .closed }
    return .dropped
}
