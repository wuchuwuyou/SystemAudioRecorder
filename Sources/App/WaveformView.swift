import AppKit

final class WaveformHistory {
    private(set) var samples = [Float](repeating: 0, count: 160)

    func append(_ peaks: [Float]) {
        let latest = peaks.suffix(samples.count).map { $0.isFinite ? min(1, max(0, $0)) : 0 }
        samples.removeFirst(latest.count)
        samples.append(contentsOf: latest)
    }

    func reset() {
        samples = [Float](repeating: 0, count: 160)
    }
}

@MainActor
final class WaveformView: NSView {
    private let history = WaveformHistory()
    var isRecording = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(L10n.string("waveform.label"))
        setAccessibilityHelp(L10n.string("waveform.help"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Storyboard initialization is unsupported.") }

    func append(_ peaks: [Float]) {
        guard isRecording else { return }
        history.append(peaks)
        needsDisplay = true
    }

    func reset() {
        history.reset()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let plot = bounds.insetBy(dx: 2, dy: 4)
        guard plot.width > 0, plot.height > 0 else { return }
        (isRecording ? NSColor.systemRed : NSColor.secondaryLabelColor).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        for direction: CGFloat in [1, -1] {
            var previous = NSPoint(x: plot.minX, y: plot.midY + direction * CGFloat(history.samples[0]) * plot.height / 2)
            path.move(to: previous)
            for index in 1..<history.samples.count {
                let point = NSPoint(x: plot.minX + CGFloat(index) * plot.width / CGFloat(history.samples.count - 1),
                                    y: plot.midY + direction * CGFloat(history.samples[index]) * plot.height / 2)
                let middleX = (previous.x + point.x) / 2
                path.curve(to: point, controlPoint1: NSPoint(x: middleX, y: previous.y),
                           controlPoint2: NSPoint(x: middleX, y: point.y))
                previous = point
            }
        }
        // Redraw only captured peaks; no interpolation animation, including under Reduce Motion.
        path.stroke()
    }
}
