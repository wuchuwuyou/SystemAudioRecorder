import Foundation

// These checks catch lost startup Stop requests, premature completion, and dropped stderr errors.
@main
struct RecordingProcessTests {
    static func main() throws {
        guard RecordingProcess.waveformValues(from: "WAVEFORM: 0,0.1,0.2,0.3,0.4,0.5,0.6,1") == [0,0.1,0.2,0.3,0.4,0.5,0.6,1] else {
            FileHandle.standardError.write(Data("FAIL: valid waveform protocol was rejected\n".utf8))
            exit(1)
        }
        precondition(RecordingProcess.waveformValues(from: "WAVEFORM: nan,0,0,0,0,0,0,0") == nil)
        precondition(RecordingProcess.waveformValues(from: "WAVEFORM: 2,0,0,0,0,0,0,0") == nil)
        precondition(RecordingProcess.waveformValues(from: "WAVEFORM: 0,0") == nil)
        precondition(RecordingProcess.waveformValues(from: "ERROR: wrong prefix") == nil)
        precondition(RecordingProcess.isEmptyCaptureError("Only silence was captured. Do not treat this as successful."))
        precondition(RecordingProcess.isEmptyCaptureError("No audio frames were received. Capture failed."))
        precondition(!RecordingProcess.isEmptyCaptureError("Cannot write captured audio: disk full."))
        precondition(!RecordingProcess.isEmptyCaptureError(nil))
        let build = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent(".build", isDirectory: true)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        let root = build.appendingPathComponent("fixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        let helper = root.appendingPathComponent("helper")
        try """
        #!/bin/sh
        sleep 0.1
        printf RECO >&2
        sleep 0.1
        printf 'RDING: ready\\n' >&2
        printf 'WAVEFORM: 0,0.1,0.2,0.3,0.4,0.5,0.6,1\\n' >&2
        IFS= read -r stop
        printf finalized > "$1"
        """.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let earlyOutput = root.appendingPathComponent("pre-stop-capture", isDirectory: true).appendingPathComponent("recording.wav")
        let earlyRecorder = try RecordingProcess(backendURL: helper, outputURL: earlyOutput)
        var earlyStarted = false
        var earlyWaveform = false
        var earlyFinished = false
        earlyRecorder.start { event in
            switch event {
            case .recording:
                earlyStarted = true
            case let .finished(exitCode, error):
                precondition(exitCode == 0 && error == nil)
                earlyFinished = true
            case let .waveform(values):
                precondition(Thread.isMainThread)
                precondition(values == [0,0.1,0.2,0.3,0.4,0.5,0.6,1])
                earlyWaveform = true
            case .stopFailed:
                preconditionFailure("Stop failed in pre-Stop marker fixture")
            }
        }
        let deadline = Date().addingTimeInterval(1)
        while !(earlyStarted && earlyWaveform) && !earlyFinished && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        let markerArrivedBeforeStop = earlyStarted && earlyWaveform && !earlyFinished
        // Stop and reap the fixture even when the expected pre-Stop marker never arrives.
        earlyRecorder.requestStop()
        runUntil { earlyFinished }
        guard markerArrivedBeforeStop else {
            FileHandle.standardError.write(Data("FAIL: RECORDING did not arrive before Stop; helper was stopped and reaped\n".utf8))
            exit(1)
        }
        let output = root.appendingPathComponent("capture", isDirectory: true).appendingPathComponent("recording.wav")
        let recorder = try RecordingProcess(backendURL: helper, outputURL: output)
        var started = false
        var finished = false
        recorder.start { event in
            precondition(Thread.isMainThread)
            switch event {
            case .recording:
                started = true
            case let .finished(exitCode, error):
                precondition(started, "Split RECORDING line was not delivered before completion")
                precondition(exitCode == 0 && error == nil)
                precondition((try? String(contentsOf: output, encoding: .utf8)) == "finalized")
                let permissions = try? FileManager.default.attributesOfItem(atPath: output.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber
                precondition(permissions?.intValue == 0o700)
                finished = true
            case .waveform:
                break
            case .stopFailed:
                preconditionFailure("Startup Stop failed")
            }
        }
        recorder.requestStop()
        runUntil { finished }

        let failingHelper = root.appendingPathComponent("failing-helper")
        try """
        #!/bin/sh
        printf 'ERROR: output failed' >&2
        exit 7
        """.write(to: failingHelper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: failingHelper.path)
        let failedOutput = root.appendingPathComponent("failed-capture", isDirectory: true).appendingPathComponent("recording.wav")
        let failedRecorder = try RecordingProcess(backendURL: failingHelper, outputURL: failedOutput)
        var failed = false
        failedRecorder.start { event in
            if case let .finished(exitCode, error) = event {
                precondition(exitCode == 7 && error == "output failed", "Final unterminated ERROR line was dropped")
                failed = true
            }
        }
        runUntil { failed }
        for code in [2, 3] {
            let emptyHelper = root.appendingPathComponent("empty-helper-\(code)")
            try "#!/bin/sh\nexit \(code)\n".write(to: emptyHelper, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: emptyHelper.path)
            let emptyOutput = root.appendingPathComponent("empty-capture-\(code)", isDirectory: true).appendingPathComponent("recording.wav")
            let emptyRecorder = try RecordingProcess(backendURL: emptyHelper, outputURL: emptyOutput)
            var emptyFinished = false
            emptyRecorder.start { event in
                if case let .finished(exitCode, error) = event {
                    precondition(exitCode == Int32(code))
                    guard RecordingProcess.isEmptyCaptureError(error) else {
                        FileHandle.standardError.write(Data("FAIL: empty capture accepted when ERROR diagnostics were unavailable\n".utf8))
                        exit(1)
                    }
                    emptyFinished = true
                }
            }
            runUntil { emptyFinished }
        }
        FileHandle.standardOutput.write(Data("PASS: RECORDING before Stop, startup Stop, split stderr, private temp directory, finalized exit, error exit, empty-capture rejection\n".utf8))
    }

    static func runUntil(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        precondition(condition(), "Helper lifecycle timed out")
    }
}
