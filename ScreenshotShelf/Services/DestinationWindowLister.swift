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
        let refreshNames = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        for name in refreshNames {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        self?.refresh()
                    }
                }
            )
        }
        observers.append(
            center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor in
                    if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                        DestinationWindowLister.rememberActivation(of: app)
                    }
                    self?.refresh()
                }
            }
        )
    }

    deinit {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func refresh() {
        DestinationWindowLister.pruneActivations()
        running = Set(SendDestination.allCases.filter { DestinationWindowLister.isRunning($0) })
        if let front = NSWorkspace.shared.frontmostApplication {
            DestinationWindowLister.rememberActivation(of: front)
        }
    }
}

enum DestinationWindowLister {
    private static var lastActivatedPIDs: [SendDestination: pid_t] = [:]

    static func isRunning(_ destination: SendDestination) -> Bool {
        !runningApplications(for: destination).isEmpty
    }

    static func matches(_ app: NSRunningApplication, destination: SendDestination) -> Bool {
        guard let bid = app.bundleIdentifier else { return false }
        return destination.lookupBundleIDs.contains(bid)
    }

    static func rememberActivation(of app: NSRunningApplication) {
        guard !app.isTerminated else { return }
        for destination in SendDestination.allCases where matches(app, destination: destination) {
            lastActivatedPIDs[destination] = app.processIdentifier
        }
    }

    static func pruneActivations() {
        for destination in SendDestination.allCases {
            guard let pid = lastActivatedPIDs[destination] else { continue }
            if NSRunningApplication(processIdentifier: pid)?.isTerminated != false {
                lastActivatedPIDs[destination] = nil
            }
        }
    }

    static func lastActivatedPID(for destination: SendDestination) -> pid_t? {
        pruneActivations()
        return lastActivatedPIDs[destination]
    }

    static func runningApplications(for destination: SendDestination) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            matches(app, destination: destination) && !app.isTerminated && app.activationPolicy == .regular
        }
    }

    static func windows(for destination: SendDestination) -> [DestinationWindow] {
        runningApplications(for: destination).flatMap { windows(in: $0, destination: destination) }
    }

    static func preferredWindow(in windows: [DestinationWindow]) -> DestinationWindow? {
        windows.first { axBool($0.axWindow, kAXMainAttribute as String) }
            ?? windows.first { axBool($0.axWindow, kAXFocusedAttribute as String) }
            ?? windows.first
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

    static func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else {
            return nil
        }
        return (value as! AXUIElement)
    }

    static func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    static func axBool(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return false
        }
        if let flag = value as? Bool {
            return flag
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return false
    }
}
