import AppKit
import ApplicationServices

enum SendResult {
    case sent
    case needsAccessibility
    case copyFailed
    case appNotRunning
}

enum ScreenshotSender {
    @MainActor
    private static var didPromptThisLaunch = false
    @MainActor
    private static var didExplainThisLaunch = false

    @MainActor
    static func send(
        item: ScreenshotItem,
        destination: SendDestination,
        window: DestinationWindow?,
        library: ScreenshotLibrary
    ) async -> SendResult {
        guard ensureAccessibility() else { return .needsAccessibility }

        let target = resolvedTarget(destination: destination, window: window)
        guard let target else { return .appNotRunning }
        guard library.copyImage(of: item) else { return .copyFailed }

        PanelDismissal.suppress = true
        defer { PanelDismissal.suppress = false }
        NSApp.keyWindow?.resignKey()
        try? await Task.sleep(nanoseconds: 80_000_000)

        activate(pid: target.pid)
        if let axWindow = target.axWindow {
            raise(axWindow)
        }
        if destination.triesComposerFocus {
            focusComposer(pid: target.pid)
        }

        try? await Task.sleep(nanoseconds: 220_000_000)
        postPaste(useControl: destination.usesControlPaste)
        return .sent
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
    }

    private static func resolvedTarget(
        destination: SendDestination,
        window: DestinationWindow?
    ) -> Target? {
        if let window {
            return Target(pid: window.pid, axWindow: window.axWindow)
        }
        if let listed = DestinationWindowLister.windows(for: destination).first {
            return Target(pid: listed.pid, axWindow: listed.axWindow)
        }
        if let app = DestinationWindowLister.runningApplications(for: destination).first {
            return Target(pid: app.processIdentifier, axWindow: nil)
        }
        return nil
    }

    private static func activate(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate(options: [.activateIgnoringOtherApps])
    }

    private static func raise(_ window: AXUIElement) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    private static func focusComposer(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        var budget = 400
        var scored: [(Int, AXUIElement)] = []
        collectTextInputs(app, depth: 0, budget: &budget, into: &scored)
        guard let best = scored.max(by: { $0.0 < $1.0 })?.1 else { return }
        AXUIElementSetAttributeValue(best, kAXFocusedAttribute as CFString, kCFBooleanTrue)
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
        if role == "AXTextArea" || role == "AXTextField" || role == "AXComboBox" {
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

    private static func postPaste(useControl: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyV: CGKeyCode = 0x09
        let flags: CGEventFlags = useControl ? .maskControl : .maskCommand

        let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
    }
}
