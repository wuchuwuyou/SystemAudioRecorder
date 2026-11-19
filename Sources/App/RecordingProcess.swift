import Darwin
import Foundation

final class RecordingProcess {
    enum Event {
        case recording
        case waveform([Float])
        case finished(exitCode: Int32, error: String?)
        case stopFailed(String)
    }

    private let process = Process()
    private let input = Pipe()
    private let errors = Pipe()
    private let outputURL: URL
    private let inputQueue = DispatchQueue(label: "local.codex.recorder.input")
    private var eventHandler: ((Event) -> Void)?

    init(backendURL: URL, outputURL: URL) throws {
        self.outputURL = outputURL
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        process.executableURL = backendURL
        process.arguments = [outputURL.path]
        process.standardInput = input
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
    }

    func start(onEvent: @escaping (Event) -> Void) {
        eventHandler = onEvent
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            defer {
                inputQueue.async { [self] in try? input.fileHandleForWriting.close() }
                try? errors.fileHandleForReading.close()
            }
            do {
                let directory = outputURL.deletingLastPathComponent()
                guard mkdir(directory.path, 0o700) == 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [
                        NSLocalizedDescriptionKey: "Cannot create a private recording directory: \(String(cString: strerror(errno)))."
                    ])
                }
                try process.run()
            } catch {
                emit(.finished(exitCode: -1, error: error.localizedDescription), to: onEvent)
                return
            }

            var pending = Data()
            var backendError: String?
            func consume(_ line: Data) {
                let text = String(decoding: line, as: UTF8.self)
                if text.hasPrefix("RECORDING:") {
                    emit(.recording, to: onEvent)
                } else if let values = Self.waveformValues(from: text) {
                    emit(.waveform(values), to: onEvent)
                } else if text.hasPrefix("ERROR:") {
                    backendError = String(text.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            do {
                // FileHandle can wait for the requested count; one byte keeps markers live.
                while let chunk = try errors.fileHandleForReading.read(upToCount: 1), !chunk.isEmpty {
                    pending.append(chunk)
                    while let newline = pending.firstIndex(of: 10) {
                        consume(Data(pending[..<newline]))
                        pending.removeSubrange(...newline)
                    }
                    // Bound diagnostics memory; the bundled helper emits short protocol lines.
                    if pending.count > 8192 { pending = Data(pending.prefix(8192)) }
                }
                if !pending.isEmpty { consume(pending) }
            } catch {
                backendError = "Cannot read recorder diagnostics: \(error.localizedDescription)"
                requestStop()
            }
            process.waitUntilExit()
            let exitCode = process.terminationReason == .exit ? process.terminationStatus : -1
            // Exit status preserves empty-capture rejection even if stderr is unavailable.
            if exitCode == 2 { backendError = "No audio frames were received." }
            if exitCode == 3 { backendError = "Only silence was captured." }
            emit(.finished(exitCode: exitCode, error: backendError), to: onEvent)
        }
    }

    static func waveformValues(from line: String) -> [Float]? {
        guard line.hasPrefix("WAVEFORM:") else { return nil }
        let parts = line.dropFirst(9).trimmingCharacters(in: .whitespaces).split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 8 else { return nil }
        let values = parts.compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == 8, values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        return values
    }

    static func isEmptyCaptureError(_ message: String?) -> Bool {
        guard let message else { return false }
        return message.contains("Only silence was captured") || message.contains("No audio frames were received")
    }

    func requestStop() {
        let handler = eventHandler
        inputQueue.async { [self] in
            do {
                try input.fileHandleForWriting.write(contentsOf: Data([10]))
            } catch {
                if let handler {
                    emit(.stopFailed(error.localizedDescription), to: handler)
                }
            }
        }
    }

    private func emit(_ event: Event, to handler: @escaping (Event) -> Void) {
        DispatchQueue.main.async { handler(event) }
    }
}
