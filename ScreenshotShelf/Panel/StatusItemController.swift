import AppKit
import Combine
import SwiftUI

enum PanelDismissal {
    static var suppress = false
}

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let library: ScreenshotLibrary
    private let settings: AppSettings

    private let statusItem: NSStatusItem
    private let panel: ShelfPanel
    private let hostingController: NSHostingController<AnyView>
    private let statusMenu = NSMenu()

    private var globalMonitor: Any?
    private var localKeyMonitor: Any?
    private var dragBeginObserver: NSObjectProtocol?
    private var dragEndObserver: NSObjectProtocol?
    private var isDragging = false
    private let destinations = DestinationCatalog()
    private let globalHotKey = GlobalHotKey()
    private var cancellables = Set<AnyCancellable>()
    private var recordingObserver: NSObjectProtocol?

    init(library: ScreenshotLibrary, settings: AppSettings) {
        self.library = library
        self.settings = settings

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        panel = ShelfPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 520))

        let root = ShelfPanelView()
            .environmentObject(library)
            .environmentObject(settings)
            .environmentObject(destinations)
        hostingController = NSHostingController(rootView: AnyView(root))
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 400, height: 520)

        super.init()

        panel.contentViewController = hostingController
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 12
        panel.contentView?.layer?.masksToBounds = true

        configureStatusItem()
        observeDragging()
        observeHotKey()
        registerOpenHotKey()
        library.onNewScreenshot = { [weak self] in
            guard let self, self.settings.openShelfOnCapture else { return }
            self.showPanel()
        }
    }

    func showPanel() {
        guard !panel.isVisible else {
            setStatusItemHighlighted(true)
            return
        }
        library.rescan()
        destinations.refresh()
        positionPanel()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        positionPanel()
        setStatusItemHighlighted(true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        installMonitors()
        setStatusItemUsesMenu(false)
        DispatchQueue.main.async { [weak self] in
            self?.positionPanel()
        }
    }

    func hidePanel(force: Bool = false) {
        if !force {
            guard !isDragging, !PanelDismissal.suppress else { return }
        }
        guard panel.isVisible else { return }
        removeMonitors()
        panel.preferredFrame = nil
        panel.orderOut(nil)
        panel.alphaValue = 1
        setStatusItemHighlighted(false)
        setStatusItemUsesMenu(true)
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.cancelTrackingWithoutAnimation()
        guard !panel.isVisible else { return }
        DispatchQueue.main.async { [weak self] in
            self?.showPanel()
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let image = NSImage(
            systemSymbolName: "camera.viewfinder",
            accessibilityDescription: "Screenshot Shelf"
        )?.withSymbolConfiguration(config)
        image?.isTemplate = true
        button.image = image
        refreshStatusItemTooltip()

        statusMenu.delegate = self
        let placeholder = NSMenuItem()
        placeholder.isHidden = true
        statusMenu.addItem(placeholder)
        setStatusItemUsesMenu(true)
    }

    private func setStatusItemUsesMenu(_ usesMenu: Bool) {
        guard let button = statusItem.button else { return }
        if usesMenu {
            button.target = nil
            button.action = nil
            statusItem.menu = statusMenu
        } else {
            statusItem.menu = nil
            button.target = self
            button.action = #selector(togglePanel)
        }
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func setStatusItemHighlighted(_ highlighted: Bool) {
        statusItem.button?.highlight(highlighted)
    }

    private func positionPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let mouseScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
        let screen = [buttonWindow.screen, mouseScreen, NSScreen.main]
            .compactMap { $0 }
            .first { $0.visibleFrame.width > 0 && $0.visibleFrame.height > 0 }
            ?? NSScreen.screens.first { $0.visibleFrame.width > 0 }
        let visible = screen?.visibleFrame ?? .zero
        guard visible.width > 0, visible.height > 0 else { return }

        let width: CGFloat = 400
        let height: CGFloat = 520
        let margin: CGFloat = 8

        let anchor: NSRect
        if buttonRect.width > 0, buttonRect.minY > 0 {
            anchor = buttonRect
        } else {
            let x = mouseScreen != nil ? NSEvent.mouseLocation.x : visible.midX
            anchor = NSRect(x: x, y: visible.maxY, width: 1, height: 1)
        }

        var x = anchor.midX - width / 2
        var y = anchor.minY - height - 5

        let minX = visible.minX + margin
        let maxX = visible.maxX - width - margin
        x = maxX >= minX ? min(max(x, minX), maxX) : minX

        let minY = visible.minY + margin
        let maxY = visible.maxY - height - margin
        y = maxY >= minY ? min(max(y, minY), maxY) : minY

        panel.applyPreferredFrame(NSRect(x: x, y: y, width: width, height: height))
    }

    private func installMonitors() {
        removeMonitors()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in
                self?.handleClickOutside(event)
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                if HotKeyRecording.isActive {
                    return event
                }
                Task { @MainActor in
                    self?.hidePanel()
                }
                return nil
            }
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private func handleClickOutside(_ event: NSEvent) {
        guard panel.isVisible, !isDragging, !PanelDismissal.suppress else { return }
        if isClickOnStatusItem() { return }
        if panel.frame.contains(NSEvent.mouseLocation) { return }
        hidePanel()
    }

    private func isClickOnStatusItem() -> Bool {
        guard let button = statusItem.button, let window = button.window else { return false }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return frame.contains(NSEvent.mouseLocation)
    }

    private func observeDragging() {
        dragBeginObserver = NotificationCenter.default.addObserver(
            forName: .screenshotShelfDragDidBegin,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isDragging = true
            }
        }
        dragEndObserver = NotificationCenter.default.addObserver(
            forName: .screenshotShelfDragDidEnd,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isDragging = false
            }
        }
    }

    private func observeHotKey() {
        settings.$openHotKey
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.registerOpenHotKey()
            }
            .store(in: &cancellables)

        recordingObserver = NotificationCenter.default.addObserver(
            forName: .hotKeyRecordingDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.registerOpenHotKey()
            }
        }
    }

    private func registerOpenHotKey() {
        let shortcut = HotKeyRecording.isActive ? nil : settings.openHotKey
        let registered = globalHotKey.update(shortcut) { [weak self] in
            Task { @MainActor in
                self?.togglePanel()
            }
        }
        settings.openHotKeyConflict = shortcut != nil && !registered
        refreshStatusItemTooltip()
    }

    private func refreshStatusItemTooltip() {
        if let shortcut = settings.openHotKey?.displayString {
            statusItem.button?.toolTip = "Screenshot Shelf · \(shortcut)"
        } else {
            statusItem.button?.toolTip = "Screenshot Shelf"
        }
    }

    deinit {
        if let dragBeginObserver {
            NotificationCenter.default.removeObserver(dragBeginObserver)
        }
        if let dragEndObserver {
            NotificationCenter.default.removeObserver(dragEndObserver)
        }
        if let recordingObserver {
            NotificationCenter.default.removeObserver(recordingObserver)
        }
    }
}
