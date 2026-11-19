import AppKit

@MainActor
final class ValidationDelegate: NSObject, NSApplicationDelegate {
    private var controller: RecorderWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let fixture = Bundle.main.url(forAuxiliaryExecutable: "FixtureBackend") else {
            preconditionFailure("Synthetic validation backend is missing.")
        }
        controller = RecorderWindowController(backendURL: fixture)
        controller?.window?.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "Synthetic Waveform Test (No Capture)"
        controller?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller?.canCloseOrQuit() == false ? .terminateCancel : .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = ValidationDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    application.run()
}
