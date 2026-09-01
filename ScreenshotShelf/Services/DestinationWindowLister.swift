import AppKit
import ApplicationServices

struct DestinationWindow: Identifiable {
    let id: String
    let destination: SendDestination
    let title: String
    let pid: pid_t
    let bundleID: String
    let appName: String
    let axWindow: AXUIElement
}

@MainActor
final class DestinationCatalog: ObservableObject {
    @Published private(set) var running: Set<SendDestination> = []

    private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        let names = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
        ]
        for name in names {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        self?.refresh()
                    }
                }
            )
        }
    }

    deinit {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func refresh() {
        running = Set(SendDestination.allCases.filter { DestinationWindowLister.isRunning($0) })
    }
}

enum DestinationWindowLister {
    static func isRunning(_ destination: SendDestination) -> Bool {
        !runningApplications(for: destination).isEmpty
    }

    static func runningApplications(for destination: SendDestination) -> [NSRunningApplication] {
        let ids = Set(destination.lookupBundleIDs)
        return NSWorkspace.shared.runningApplications.filter { app in
            guard let bid = app.bundleIdentifier, ids.contains(bid) else { return false }
            return !app.isTerminated && app.activationPolicy == .regular
        }
    }

    static func windows(for destination: SendDestination) -> [DestinationWindow] {
        runningApplications(for: destination).flatMap { windows(in: $0, destination: destination) }
    }

    private static func windows(
        in app: NSRunningApplication,
        destination: SendDestination
    ) -> [DestinationWindow] {
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value)
        guard status == .success, let axWindows = value as? [AXUIElement] else { return [] }

        let appName = app.localizedName ?? destination.title
        let bundleID = app.bundleIdentifier ?? ""

        return axWindows.enumerated().compactMap { index, window in
            if let role = axString(window, kAXRoleAttribute as String), role != "AXWindow" {
                return nil
            }
            let rawTitle = axString(window, kAXTitleAttribute as String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = rawTitle.isEmpty ? appName : rawTitle
            return DestinationWindow(
                id: "\(destination.rawValue):\(bundleID):\(pid):\(index):\(title)",
                destination: destination,
                title: title,
                pid: pid,
                bundleID: bundleID,
                appName: appName,
                axWindow: window
            )
        }
    }

    static func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
