import AppKit

// Drawing must keep real peak order, remain flat for silence, and never grow with recording duration.
@main
struct WaveformHistoryTests {
    @MainActor
    static func main() {
        let history = WaveformHistory()
        precondition(history.samples.count == 160 && history.samples.allSatisfy { $0 == 0 })
        history.append([0, 0, 0, 0])
        precondition(history.samples.allSatisfy { $0 == 0 }, "Silence must stay flat")
        history.append([0.2, 0.8, 0.1])
        precondition(Array(history.samples.suffix(3)) == [0.2, 0.8, 0.1], "Actual peak order was lost")
        history.append([-1, 2, .nan, .infinity])
        precondition(Array(history.samples.suffix(4)) == [0, 1, 0, 0], "Invalid amplitude reached drawing")
        history.append(Array(repeating: 0.4, count: 10_000) + [0.7])
        precondition(history.samples.count == 160 && history.samples.first == 0.4 && history.samples.last == 0.7,
                     "Long recording did not retain only the latest real peaks")
        history.append([])
        precondition(history.samples.count == 160 && history.samples.last == 0.7)
        history.reset()
        precondition(history.samples.count == 160 && history.samples.allSatisfy { $0 == 0 },
                     "A new capture inherited the previous waveform")
        let view = WaveformView(frame: NSRect(x: 0, y: 0, width: 160, height: 64))
        let idle = render(view)
        view.append([1, 0.5, 1])
        precondition(render(view) == idle, "Idle input must not invent a waveform")
        view.isRecording = true
        let recordingSilence = render(view)
        view.append(Array(repeating: 0, count: 160))
        precondition(render(view) == recordingSilence, "Captured silence must render flat")
        view.append([0.2, 0.8, 0.4, 1, 0.3])
        precondition(render(view) != recordingSilence, "Real captured peaks were not drawn")
        view.isRecording = false
        let stopped = render(view)
        view.append(Array(repeating: 1, count: 160))
        precondition(render(view) == stopped, "Stopped recording did not freeze its real waveform")
        view.reset()
        precondition(render(view) == idle, "Reset did not render the flat idle waveform")
        FileHandle.standardOutput.write(Data("PASS: real peak history, silence, finite clamping, bounded retention, idle gating, real rendering, stop freeze, new-capture reset\n".utf8))
    }

    @MainActor
    private static func render(_ view: WaveformView) -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 64,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 640, bitsPerPixel: 32)!
        memset(bitmap.bitmapData!, 0, bitmap.bytesPerRow * bitmap.pixelsHigh)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        return Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }
}
