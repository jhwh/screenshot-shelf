import AppKit
import ApplicationServices
import os

enum SendResult {
    case sent
    case needsAccessibility
    case copyFailed
    case appNotRunning
    case targetDidNotActivate

    func overlayMessage(for destination: SendDestination) -> String {
        switch self {
        case .sent:
            return "Sent to \(destination.title)"
        case .needsAccessibility:
            return "Accessibility required"
        case .copyFailed:
            return "Couldn't copy image"
        case .appNotRunning:
            return "\(destination.title) is not running"
        case .targetDidNotActivate:
            return "Nothing to paste into"
        }
    }
}

enum ScreenshotSender {
    @MainActor
    private static var didPromptThisLaunch = false
    @MainActor
    private static var didExplainThisLaunch = false
    @MainActor
    private static var sendBusy = false
    @MainActor
    private static var sendWaiters: [CheckedContinuation<Void, Never>] = []

    private static let activationTimeout: Duration = .milliseconds(1500)
    private static let activationPoll: Duration = .milliseconds(40)
    private static let textInputRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox"]
    private static let log = Logger(subsystem: "pl.mendrela.screenshotshelf", category: "send")

    @MainActor
    static func send(
        item: ScreenshotItem,
        destination: SendDestination,
        window: DestinationWindow?,
        library: ScreenshotLibrary
    ) async -> SendResult {
        await withSendLock {
            await performSend(
                item: item,
                destination: destination,
                window: window,
                library: library
            )
        }
    }

    @MainActor
    static func ensureAccessibility() -> Bool {
        if AXIsProcessTrusted() { return true }

        if !didPromptThisLaunch {
            didPromptThisLaunch = true
            PanelDismissal.suppress = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            PanelDismissal.suppress = false
            if AXIsProcessTrusted() { return true }
        }

        if !didExplainThisLaunch {
            didExplainThisLaunch = true
            explainTrustMismatch()
        }
        return AXIsProcessTrusted()
    }

    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @MainActor
    private static func withSendLock<T>(_ work: () async -> T) async -> T {
        if sendBusy {
            await withCheckedContinuation { continuation in
                sendWaiters.append(continuation)
            }
        } else {
            sendBusy = true
        }

        defer {
            if sendWaiters.isEmpty {
                sendBusy = false
            } else {
                sendWaiters.removeFirst().resume()
            }
        }

        return await work()
    }

    @MainActor
    private static func performSend(
        item: ScreenshotItem,
        destination: SendDestination,
        window: DestinationWindow?,
        library: ScreenshotLibrary
    ) async -> SendResult {
        let started = ContinuousClock.now
        log.info("send start destination=\(destination.rawValue, privacy: .public) window=\(window?.title ?? "auto", privacy: .public)")
        log.info("frontmost before=\(frontmostDescription(), privacy: .public)")

        guard ensureAccessibility() else {
            log.error("send abort needsAccessibility")
            return .needsAccessibility
        }

        let target = resolvedTarget(destination: destination, window: window)
        guard let target else {
            log.error("send abort appNotRunning destination=\(destination.rawValue, privacy: .public)")
            return .appNotRunning
        }
        guard let app = NSRunningApplication(processIdentifier: target.pid), !app.isTerminated else {
            log.error("send abort target pid \(target.pid) gone")
            return .appNotRunning
        }
        log.info("target pid=\(target.pid) bundle=\(app.bundleIdentifier ?? "?", privacy: .public) raise=\(target.shouldRaise)")
        guard library.copyImage(of: item) else {
            log.error("send abort copyFailed")
            return .copyFailed
        }

        PanelDismissal.suppress = true
        defer { PanelDismissal.suppress = false }

        let raiseWindow = target.shouldRaise ? target.axWindow : nil
        activate(app, window: raiseWindow)
        NotificationCenter.default.post(name: .screenshotShelfHideForSend, object: nil)
        log.info("hid shelf after activate")

        let becameFrontmost = await waitUntilDestinationFrontmost(
            destination,
            preferredPid: target.pid,
            raiseWindow: raiseWindow
        )
        log.info("frontmost after wait=\(frontmostDescription(), privacy: .public) becameFrontmost=\(becameFrontmost)")

        guard let liveApp = NSRunningApplication(processIdentifier: target.pid), !liveApp.isTerminated else {
            log.error("send abort target died pid=\(target.pid)")
            return .targetDidNotActivate
        }

        let pastePid = frontmostDestinationApp(destination)?.processIdentifier ?? target.pid
        if destination.triesComposerFocus {
            let before = focusedRole(pid: pastePid) ?? "none"
            log.info("focused role before composer=\(before, privacy: .public) pid=\(pastePid)")
            focusComposer(pid: pastePid)
            try? await Task.sleep(for: activationPoll)
            let after = focusedRole(pid: pastePid) ?? "none"
            log.info("focused role after composer=\(after, privacy: .public)")
        }

        guard let stillLive = NSRunningApplication(processIdentifier: pastePid), !stillLive.isTerminated else {
            log.error("send abort paste pid \(pastePid) gone")
            return .targetDidNotActivate
        }

        let viaHID = frontmostDestinationApp(destination) != nil
        postPaste(pid: pastePid, useControl: destination.usesControlPaste, viaHID: viaHID)
        let elapsedMs = started.duration(to: ContinuousClock.now) / .milliseconds(1)
        log.info("send sent destination=\(destination.rawValue, privacy: .public) path=\(viaHID ? "hid" : "pid", privacy: .public) elapsedMs=\(Int(elapsedMs))")
        return .sent
    }

    @MainActor
    private static func explainTrustMismatch() {
        PanelDismissal.suppress = true
        let alert = NSAlert()
        alert.messageText = "This copy is not trusted yet"
        alert.informativeText = """
        The Accessibility toggle can stay on for an old ad-hoc build while this signed copy is still untrusted.

        Remove Screenshot Shelf from Accessibility (select it, press −), then enable the prompt for this copy.

        Running from:
        \(Bundle.main.bundlePath)
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")
        let response = alert.runModal()
        PanelDismissal.suppress = false
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    static func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private struct Target {
        let pid: pid_t
        let axWindow: AXUIElement?
        let shouldRaise: Bool
    }

    private static func resolvedTarget(
        destination: SendDestination,
        window: DestinationWindow?
    ) -> Target? {
        if let window {
            return Target(pid: window.pid, axWindow: window.axWindow, shouldRaise: true)
        }

        let windows = DestinationWindowLister.windows(for: destination)

        if let front = NSWorkspace.shared.frontmostApplication,
           DestinationWindowLister.matches(front, destination: destination)
        {
            let pid = front.processIdentifier
            let axWindow = DestinationWindowLister.preferredWindow(in: windows.filter { $0.pid == pid })?.axWindow
            return Target(pid: pid, axWindow: axWindow, shouldRaise: false)
        }

        if let pid = DestinationWindowLister.lastActivatedPID(for: destination),
           NSRunningApplication(processIdentifier: pid)?.isTerminated == false
        {
            let axWindow = DestinationWindowLister.preferredWindow(in: windows.filter { $0.pid == pid })?.axWindow
            return Target(pid: pid, axWindow: axWindow, shouldRaise: false)
        }

        if let preferred = DestinationWindowLister.preferredWindow(in: windows) {
            return Target(pid: preferred.pid, axWindow: preferred.axWindow, shouldRaise: false)
        }

        if let app = DestinationWindowLister.runningApplications(for: destination).first {
            return Target(pid: app.processIdentifier, axWindow: nil, shouldRaise: false)
        }
        return nil
    }

    private static func activate(_ app: NSRunningApplication, window: AXUIElement?) {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if let window {
            raise(window)
        } else if let focused = DestinationWindowLister.axElement(axApp, kAXFocusedWindowAttribute as String) {
            raise(focused)
        }
        app.activate()
        log.info("activated pid=\(app.processIdentifier) bundle=\(app.bundleIdentifier ?? "?", privacy: .public)")
    }

    private static func frontmostDestinationApp(_ destination: SendDestination) -> NSRunningApplication? {
        guard let front = NSWorkspace.shared.frontmostApplication,
              DestinationWindowLister.matches(front, destination: destination)
        else {
            return nil
        }
        return front
    }

    private static func frontmostDescription() -> String {
        guard let front = NSWorkspace.shared.frontmostApplication else { return "none" }
        return "\(front.bundleIdentifier ?? "?") pid=\(front.processIdentifier)"
    }

    private static func canPaste(into destination: SendDestination, preferredPid: pid_t) -> Bool {
        if frontmostDestinationApp(destination) != nil {
            return true
        }
        guard let front = NSWorkspace.shared.frontmostApplication, front.activationPolicy == .regular else {
            return NSRunningApplication(processIdentifier: preferredPid)?.isActive == true
        }
        if DestinationWindowLister.matches(front, destination: destination) {
            return true
        }
        return false
    }

    private static func waitUntilDestinationFrontmost(
        _ destination: SendDestination,
        preferredPid: pid_t,
        raiseWindow: AXUIElement?
    ) async -> Bool {
        let deadline = ContinuousClock.now + activationTimeout
        while ContinuousClock.now < deadline {
            if canPaste(into: destination, preferredPid: preferredPid) {
                return true
            }
            guard let app = NSRunningApplication(processIdentifier: preferredPid), !app.isTerminated else {
                return false
            }
            activate(app, window: raiseWindow)
            try? await Task.sleep(for: activationPoll)
        }
        return canPaste(into: destination, preferredPid: preferredPid)
    }

    private static func raise(_ window: AXUIElement) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    private static func focusedRole(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        guard let focused = DestinationWindowLister.axElement(app, kAXFocusedUIElementAttribute as String) else {
            return nil
        }
        return DestinationWindowLister.axString(focused, kAXRoleAttribute as String)
    }

    private static func focusComposer(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        if let focused = DestinationWindowLister.axElement(app, kAXFocusedUIElementAttribute as String) {
            let role = DestinationWindowLister.axString(focused, kAXRoleAttribute as String) ?? ""
            if textInputRoles.contains(role) {
                log.info("focusComposer skip already in \(role, privacy: .public)")
                return
            }
            log.info("focusComposer heuristic current role=\(role, privacy: .public)")
        } else {
            log.info("focusComposer heuristic no focused element")
        }

        let searchRoot = DestinationWindowLister.axElement(app, kAXFocusedWindowAttribute as String) ?? app
        var budget = 400
        var scored: [(Int, AXUIElement)] = []
        collectTextInputs(searchRoot, depth: 0, budget: &budget, into: &scored)
        guard let best = scored.max(by: { $0.0 < $1.0 })?.1 else {
            log.info("focusComposer found no text input")
            return
        }
        AXUIElementSetAttributeValue(best, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        log.info("focusComposer set score=\(scored.max(by: { $0.0 < $1.0 })?.0 ?? 0)")
    }

    private static func collectTextInputs(
        _ element: AXUIElement,
        depth: Int,
        budget: inout Int,
        into result: inout [(Int, AXUIElement)]
    ) {
        guard budget > 0, depth < 25 else { return }
        budget -= 1

        let role = DestinationWindowLister.axString(element, kAXRoleAttribute as String) ?? ""
        if textInputRoles.contains(role) {
            result.append((scoreComposer(element), element))
        }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenValue
        ) == .success,
            let children = childrenValue as? [AXUIElement]
        else { return }

        for child in children {
            collectTextInputs(child, depth: depth + 1, budget: &budget, into: &result)
        }
    }

    private static func scoreComposer(_ element: AXUIElement) -> Int {
        let blob = [
            DestinationWindowLister.axString(element, kAXDescriptionAttribute as String),
            DestinationWindowLister.axString(element, kAXPlaceholderValueAttribute as String),
            DestinationWindowLister.axString(element, kAXIdentifierAttribute as String),
            DestinationWindowLister.axString(element, kAXTitleAttribute as String),
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        var score = 1
        for word in ["composer", "chat", "agent", "ask", "message", "plan", "prompt"] {
            if blob.contains(word) { score += 3 }
        }
        for word in ["find", "search", "replace", "terminal", "output"] {
            if blob.contains(word) { score -= 5 }
        }
        return score
    }

    private static func postPaste(pid: pid_t, useControl: Bool, viaHID: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyV: CGKeyCode = 0x09
        let flags: CGEventFlags = useControl ? .maskControl : .maskCommand

        let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true)
        down?.flags = flags
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        up?.flags = flags

        if viaHID {
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            log.info("paste hid pid=\(pid)")
        } else {
            down?.postToPid(pid)
            up?.postToPid(pid)
            log.info("paste postToPid pid=\(pid)")
        }
    }
}
