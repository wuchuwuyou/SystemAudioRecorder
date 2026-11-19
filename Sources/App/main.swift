import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var recorderWindow: RecorderWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: L10n.string("app.title"))
        applicationMenu.addItem(withTitle: L10n.format("menu.quit", L10n.string("app.title")), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)
        NSApp.mainMenu = menu

        guard let backendURL = Bundle.main.url(forAuxiliaryExecutable: "AudioRecorderBackend") else {
            let alert = NSAlert()
            alert.messageText = L10n.string("helper.missingTitle")
            alert.informativeText = L10n.string("helper.missingMessage")
            alert.addButton(withTitle: L10n.string("action.ok"))
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        recorderWindow = RecorderWindowController(backendURL: backendURL)
        recorderWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        recorderWindow?.canCloseOrQuit() == false ? .terminateCancel : .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    application.run()
}
