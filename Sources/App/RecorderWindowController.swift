import AppKit
import UniformTypeIdentifiers

@MainActor
final class RecorderWindowController: NSWindowController, NSWindowDelegate {
    private enum State {
        case idle, starting, recording, stopping, pending, saving
    }

    private let backendURL: URL
    private var state: State = .idle
    private var recorder: RecordingProcess?
    private var recordingURL: URL?
    private var pendingURL: URL?
    private var partialError: String?
    private var startedAt: TimeInterval?
    private var timer: Timer?
    private var presentingSave = false
    private var presentingAlert = false
    private let mainButton = NSButton(title: "", target: nil, action: nil)
    private let infoButton = NSButton(title: "", target: nil, action: nil)
    private let waveformView = WaveformView(frame: .zero)
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let elapsedLabel = NSTextField(labelWithString: "00:00:00")
    private let infoPopover = NSPopover()
    private let infoDetail = NSTextField(wrappingLabelWithString: "")

    init(backendURL: URL) {
        self.backendURL = backendURL
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = L10n.string("app.title")
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        configureContent()
        configureInformation()
        setStatus("status.ready")
        updateControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Storyboard initialization is unsupported.") }

    private func configureContent() {
        guard let content = window?.contentView else { return }
        window?.backgroundColor = .windowBackgroundColor
        elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        elapsedLabel.textColor = .secondaryLabelColor
        elapsedLabel.setAccessibilityLabel(L10n.string("elapsed.label"))
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.maximumNumberOfLines = 2
        statusLabel.preferredMaxLayoutWidth = 312
        statusLabel.setAccessibilityLabel(L10n.string("status.label"))
        mainButton.target = self
        mainButton.action = #selector(activateMainControl)
        mainButton.bezelStyle = .circular
        mainButton.isBordered = false
        mainButton.imagePosition = .imageOnly
        mainButton.imageScaling = .scaleProportionallyDown
        mainButton.focusRingType = .exterior
        mainButton.refusesFirstResponder = false
        mainButton.keyEquivalent = " "
        mainButton.keyEquivalentModifierMask = []
        mainButton.setAccessibilityIdentifier("recordingControl")
        infoButton.target = self
        infoButton.action = #selector(showInformation)
        infoButton.isBordered = false
        infoButton.imagePosition = .imageOnly
        infoButton.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: L10n.string("action.info"))
        infoButton.contentTintColor = .secondaryLabelColor
        infoButton.focusRingType = .exterior
        infoButton.refusesFirstResponder = false
        infoButton.toolTip = L10n.string("action.info")
        infoButton.setAccessibilityLabel(L10n.string("action.info"))
        infoButton.setAccessibilityIdentifier("recordingInfo")
        infoButton.keyEquivalent = "i"
        infoButton.keyEquivalentModifierMask = .command
        for view in [waveformView, elapsedLabel, mainButton, statusLabel, infoButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            infoButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            infoButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            infoButton.widthAnchor.constraint(equalToConstant: 24),
            infoButton.heightAnchor.constraint(equalToConstant: 24),
            waveformView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            waveformView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            waveformView.topAnchor.constraint(equalTo: content.topAnchor, constant: 36),
            waveformView.heightAnchor.constraint(equalToConstant: 64),
            elapsedLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            elapsedLabel.topAnchor.constraint(equalTo: waveformView.bottomAnchor, constant: 8),
            mainButton.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            mainButton.topAnchor.constraint(equalTo: elapsedLabel.bottomAnchor, constant: 10),
            mainButton.widthAnchor.constraint(equalToConstant: 52),
            mainButton.heightAnchor.constraint(equalToConstant: 52),
            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            statusLabel.topAnchor.constraint(equalTo: mainButton.bottomAnchor, constant: 8),
            statusLabel.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -12)
        ])
        mainButton.nextKeyView = infoButton
        infoButton.nextKeyView = mainButton
        window?.initialFirstResponder = mainButton
    }

    private func configureInformation() {
        let disclosure = NSTextField(wrappingLabelWithString: L10n.string("help.disclosure"))
        let instructions = NSTextField(wrappingLabelWithString: L10n.string("help.instructions"))
        let keyboard = NSTextField(wrappingLabelWithString: L10n.string("help.keyboard"))
        for label in [disclosure, instructions, keyboard, infoDetail] {
            label.font = .systemFont(ofSize: 12)
            label.preferredMaxLayoutWidth = 276
        }
        disclosure.font = .systemFont(ofSize: 13, weight: .medium)
        keyboard.textColor = .secondaryLabelColor
        infoDetail.textColor = .secondaryLabelColor
        infoDetail.maximumNumberOfLines = 8
        let stack = NSStackView(views: [disclosure, instructions, keyboard, infoDetail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let controller = NSViewController()
        controller.view = NSView()
        controller.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: 276),
            stack.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: controller.view.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor, constant: -16)
        ])
        infoPopover.behavior = .transient
        infoPopover.contentViewController = controller
    }

    @objc private func showInformation() {
        if infoPopover.isShown {
            infoPopover.performClose(nil)
            return
        }
        resizeInformation()
        infoPopover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        infoPopover.show(relativeTo: infoButton.bounds, of: infoButton, preferredEdge: .maxY)
    }

    private func resizeInformation() {
        guard let view = infoPopover.contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        infoPopover.contentSize = view.fittingSize
    }

    private func setStatus(_ key: String, detail: String? = nil) {
        statusLabel.stringValue = L10n.string(key)
        let message = detail ?? statusLabel.stringValue
        statusLabel.toolTip = message
        statusLabel.setAccessibilityHelp(message)
        infoDetail.stringValue = message
        infoDetail.toolTip = message
        if infoPopover.isShown { resizeInformation() }
    }

    @objc private func activateMainControl() {
        switch state {
        case .idle: startRecording()
        case .starting, .recording, .pending: stopOrSave()
        case .stopping, .saving: break
        }
    }

    @objc private func startRecording() {
        guard state == .idle else { return }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SystemAudioRecorder-\(UUID().uuidString)", isDirectory: true)
        let output = directory.appendingPathComponent("recording.wav")
        do {
            let recorder = try RecordingProcess(backendURL: backendURL, outputURL: output)
            self.recorder = recorder
            recordingURL = output
            partialError = nil
            startedAt = nil
            elapsedLabel.stringValue = "00:00:00"
            waveformView.reset()
            state = .starting
            setStatus("status.starting", detail: L10n.string("detail.starting"))
            updateControls()
            recorder.start { [weak self, weak recorder] event in
                guard let this = self, let recorder, this.recorder === recorder else { return }
                this.handle(event)
            }
        } catch {
            setStatus("status.startFailed", detail: L10n.format("error.start", error.localizedDescription))
        }
    }

    private func handle(_ event: RecordingProcess.Event) {
        switch event {
        case .recording:
            guard state == .starting || state == .stopping else { return }
            if startedAt == nil {
                startedAt = ProcessInfo.processInfo.systemUptime
                timer = Timer.scheduledTimer(timeInterval: 0.25, target: self,
                                             selector: #selector(updateElapsed), userInfo: nil, repeats: true)
                if let timer { RunLoop.main.add(timer, forMode: .common) }
            }
            if state == .starting {
                state = .recording
                setStatus("status.recording")
            }
            updateControls()
        case let .waveform(peaks):
            guard state == .recording else { return }
            waveformView.append(peaks)
        case let .finished(exitCode, error):
            updateElapsed()
            timer?.invalidate()
            timer = nil
            recorder = nil
            state = .stopping
            setStatus("status.checking")
            updateControls()
            guard let output = recordingURL else { return }
            let failure = exitCode == 0 && error == nil ? nil : (error ?? L10n.format("error.exit", exitCode))
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let knownEmpty = RecordingProcess.isEmptyCaptureError(failure)
                let usable = !knownEmpty && RecordingFileStore().isUsableRecording(at: output)
                var cleanupError: Error?
                if knownEmpty {
                    do { try RecordingSaveOperation.removeOwnedTemporaryRecording(at: output) }
                    catch { cleanupError = error }
                }
                let cleanupFailure = cleanupError
                DispatchQueue.main.async {
                    guard let this = self else { return }
                    this.recordingURL = nil
                    if usable {
                        this.pendingURL = output
                        this.partialError = failure
                        this.state = .pending
                        this.setStatus(failure == nil ? "status.pending" : "status.partialPending", detail: failure.map {
                            L10n.format("detail.partialPending", L10n.recordingError($0))
                        } ?? L10n.string("detail.pending"))
                        this.updateControls()
                        this.presentSavePanel()
                    } else {
                        this.state = .idle
                        var detail = L10n.format("error.capture", failure.map { L10n.recordingError($0) }
                                                 ?? L10n.string("error.noUsableAudio"))
                        if cleanupFailure != nil { detail += " " + L10n.string("error.cleanupKept") }
                        this.setStatus(knownEmpty ? "status.noAudio" : "status.failed", detail: detail)
                        if let cleanupFailure {
                            this.showAlert(title: L10n.string("alert.captureCleanupTitle"),
                                           message: L10n.format("alert.cleanupDetail", cleanupFailure.localizedDescription,
                                                                output.deletingLastPathComponent().path))
                        }
                        this.updateControls()
                    }
                }
            }
        case let .stopFailed(error):
            if state == .stopping && recorder != nil {
                state = startedAt == nil ? .starting : .recording
                setStatus("status.stopFailed", detail: L10n.format("error.stop", L10n.recordingError(error)))
                updateControls()
            }
        }
    }

    @objc private func stopOrSave() {
        if state == .pending {
            presentSavePanel()
        } else if state == .starting || state == .recording {
            state = .stopping
            setStatus("status.stopping", detail: L10n.string("detail.stopping"))
            updateControls()
            recorder?.requestStop()
        }
    }

    @objc private func updateElapsed() {
        guard let startedAt else { return }
        let seconds = max(0, Int(ProcessInfo.processInfo.systemUptime - startedAt))
        elapsedLabel.stringValue = String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    private func presentSavePanel() {
        guard state == .pending, !presentingSave, let source = pendingURL, window != nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = L10n.string(partialError == nil ? "save.title" : "save.partialTitle")
        panel.prompt = L10n.string("action.save")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let prefix = L10n.string(partialError == nil ? "save.filename" : "save.partialFilename")
        panel.nameFieldStringValue = "\(prefix)_\(formatter.string(from: Date())).wav"
        panel.message = partialError.map { L10n.format("save.partialMessage", L10n.recordingError($0)) }
            ?? L10n.string("save.message")
        presentingSave = true
        updateControls()
        // Run outside a main-dispatch callback so the modal panel can receive XPC replies.
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                let response = panel.runModal()
                guard let this = self else { return }
                this.presentingSave = false
                guard response == .OK, let destination = panel.url else {
                    this.setStatus(this.partialError == nil ? "status.notSaved" : "status.partialNotSaved",
                                   detail: L10n.string(this.partialError == nil ? "detail.notSaved" : "detail.partialNotSaved"))
                    this.updateControls()
                    return
                }
                this.confirmReplacementOrSave(from: source, to: destination)
            }
        }
    }

    private func confirmReplacementOrSave(from source: URL, to destination: URL) {
        state = .saving
        setStatus("status.destination")
        updateControls()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let exists = FileManager.default.fileExists(atPath: destination.path)
            DispatchQueue.main.async {
                guard let this = self, let window = this.window else { return }
                guard exists else {
                    this.save(from: source, to: destination, replacementConfirmed: false)
                    return
                }
                let alert = NSAlert()
                alert.messageText = L10n.string("alert.replaceTitle")
                alert.informativeText = L10n.format("alert.replaceMessage", destination.path)
                alert.alertStyle = .warning
                alert.addButton(withTitle: L10n.string("action.cancel")).keyEquivalent = "\r"
                alert.addButton(withTitle: L10n.string("action.replace")).keyEquivalent = ""
                this.presentingSave = true
                this.setStatus("status.replace", detail: L10n.string("detail.replace"))
                alert.beginSheetModal(for: window) { [weak self] response in
                    guard let this = self else { return }
                    this.presentingSave = false
                    guard response == .alertSecondButtonReturn else {
                        this.state = .pending
                        this.setStatus("status.replaceCanceled", detail: L10n.string("detail.replaceCanceled"))
                        this.updateControls()
                        return
                    }
                    this.save(from: source, to: destination, replacementConfirmed: true)
                }
            }
        }
    }

    private func save(from source: URL, to destination: URL, replacementConfirmed: Bool) {
        state = .saving
        setStatus("status.saving")
        updateControls()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                try RecordingSaveOperation.save(from: source, to: destination, replacementConfirmed: replacementConfirmed)
            }
            DispatchQueue.main.async {
                guard let this = self else { return }
                switch result {
                case let .success(cleanupError):
                    this.pendingURL = nil
                    this.state = .idle
                    var detail = L10n.format(this.partialError == nil ? "detail.saved" : "detail.partialSaved", destination.path)
                    if cleanupError != nil { detail += " " + L10n.string("error.cleanupIncomplete") }
                    this.setStatus(this.partialError == nil ? "status.saved" : "status.partialSaved", detail: detail)
                    if let cleanupError {
                        this.showAlert(title: L10n.string("alert.savedCleanupTitle"),
                                       message: L10n.format("alert.savedCleanupMessage", cleanupError.localizedDescription,
                                                            source.deletingLastPathComponent().path))
                    }
                case let .failure(error):
                    this.state = .pending
                    this.setStatus("status.saveFailed", detail: L10n.format("error.save", error.localizedDescription))
                    this.showAlert(title: L10n.string("alert.saveFailedTitle"),
                                   message: L10n.format("alert.saveFailedMessage", error.localizedDescription, source.path))
                }
                this.updateControls()
            }
        }
    }

    private func updateControls() {
        let symbol: String
        let label: String
        switch state {
        case .idle:
            symbol = "record.circle.fill"
            label = L10n.string("action.record")
            waveformView.reset()
        case .starting, .recording:
            symbol = "stop.circle.fill"
            label = L10n.string("action.stop")
        case .stopping:
            symbol = "stop.circle.fill"
            label = L10n.string("action.finalizing")
        case .pending, .saving:
            symbol = "arrow.down.circle.fill"
            label = L10n.string(state == .pending ? "action.save" : "action.saving")
        }
        mainButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: 48, weight: .regular))
        mainButton.contentTintColor = state == .pending || state == .saving ? .controlAccentColor : .systemRed
        mainButton.toolTip = label
        mainButton.setAccessibilityLabel(label)
        mainButton.isEnabled = !presentingSave && (state == .idle || state == .starting || state == .recording || state == .pending)
        waveformView.isRecording = state == .recording
    }

    func canCloseOrQuit() -> Bool {
        guard state == .idle && pendingURL == nil else {
            let message: String
            if state == .saving {
                message = L10n.string("alert.waitForSave")
            } else if let pendingURL {
                message = L10n.format("alert.unsaved", pendingURL.path)
            } else {
                message = L10n.string("alert.active")
            }
            showAlert(title: L10n.string("alert.cannotCloseTitle"), message: message)
            return false
        }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        canCloseOrQuit()
    }

    private func showAlert(title: String, message: String) {
        guard !presentingAlert, let window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        // Critical alerts remain visible even above an open Save panel.
        alert.alertStyle = .critical
        alert.addButton(withTitle: L10n.string("action.ok"))
        presentingAlert = true
        alert.beginSheetModal(for: window) { [weak self] _ in self?.presentingAlert = false }
    }
}
