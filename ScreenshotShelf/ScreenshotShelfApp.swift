import AppKit
import SwiftUI

@main
struct ScreenshotShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let library = ScreenshotLibrary()

    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        library.configure(settings: settings)
        library.start()
        statusItemController = StatusItemController(library: library, settings: settings)
    }

    func applicationWillTerminate(_ notification: Notification) {
        library.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItemController?.showPanel()
        return false
    }
}
