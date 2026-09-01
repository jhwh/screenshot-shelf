import AppKit
import SwiftUI

enum SendDestinationMenu {
    static func popUp(
        windows: [DestinationWindow],
        send: @escaping (DestinationWindow) -> Void
    ) {
        let menu = NSMenu()
        let targets = windows.map { window in
            MenuTarget { send(window) }
        }
        MenuTarget.retain(targets)
        for (window, target) in zip(windows, targets) {
            let item = NSMenuItem(
                title: window.title,
                action: #selector(MenuTarget.invoke),
                keyEquivalent: ""
            )
            item.target = target
            menu.addItem(item)
        }

        if let event = NSApp.currentEvent, let view = event.window?.contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        } else if let window = NSApp.keyWindow {
            let point = window.mouseLocationOutsideOfEventStream
            menu.popUp(positioning: nil, at: point, in: window.contentView)
        }
    }

    static func makeNSMenu(
        destinations: [SendDestination],
        running: Set<SendDestination>,
        send: @escaping (SendDestination, DestinationWindow?) -> Void
    ) -> NSMenu {
        let menu = NSMenu(title: "Send to")
        var targets: [MenuTarget] = []

        for destination in destinations {
            let item = NSMenuItem(
                title: destination.title,
                action: nil,
                keyEquivalent: ""
            )
            item.image = NSImage(
                systemSymbolName: destination.symbolName,
                accessibilityDescription: destination.title
            )

            if !running.contains(destination) {
                item.isEnabled = false
                menu.addItem(item)
                continue
            }

            let windows = DestinationWindowLister.windows(for: destination)
            if windows.count > 1 {
                let submenu = NSMenu()
                for window in windows {
                    let target = MenuTarget { send(destination, window) }
                    targets.append(target)
                    let windowItem = NSMenuItem(
                        title: window.title,
                        action: #selector(MenuTarget.invoke),
                        keyEquivalent: ""
                    )
                    windowItem.target = target
                    submenu.addItem(windowItem)
                }
                item.submenu = submenu
            } else {
                let target = MenuTarget { send(destination, windows.first) }
                targets.append(target)
                item.action = #selector(MenuTarget.invoke)
                item.target = target
            }
            menu.addItem(item)
        }

        MenuTarget.retain(targets)
        return menu
    }
}

struct SendDestinationChips: View {
    let item: ScreenshotItem
    var onSent: (SendDestination) -> Void

    @EnvironmentObject private var library: ScreenshotLibrary
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var catalog: DestinationCatalog

    var body: some View {
        let destinations = settings.enabledDestinationsInOrder
        if destinations.count == 1, let destination = destinations.first {
            SendDestinationButton(
                destination: destination,
                running: catalog.running.contains(destination),
                style: .primary
            ) {
                handleClick(destination)
            }
        } else {
            VStack(spacing: 5) {
                ForEach(destinations) { destination in
                    SendDestinationButton(
                        destination: destination,
                        running: catalog.running.contains(destination),
                        style: destinations.count <= 2 ? .primary : .compact
                    ) {
                        handleClick(destination)
                    }
                }
            }
        }
    }

    private func handleClick(_ destination: SendDestination) {
        let windows = DestinationWindowLister.windows(for: destination)
        if windows.count > 1 {
            SendDestinationMenu.popUp(windows: windows) { window in
                Task { await send(destination, window: window) }
            }
            return
        }
        Task { await send(destination, window: windows.first) }
    }

    private func send(_ destination: SendDestination, window: DestinationWindow?) async {
        let result = await ScreenshotSender.send(
            item: item,
            destination: destination,
            window: window,
            library: library
        )
        if result == .sent {
            onSent(destination)
        }
    }
}

private struct SendDestinationButton: View {
    enum Style {
        case primary
        case compact
    }

    let destination: SendDestination
    let running: Bool
    let style: Style
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: style == .primary ? 7 : 5) {
                Image(systemName: running ? "paperplane.fill" : destination.symbolName)
                    .font(style == .primary ? .caption.weight(.semibold) : .caption2.weight(.semibold))
                Text(style == .primary ? destination.sendTitle : destination.compactSendTitle)
                    .font(style == .primary ? .caption.weight(.semibold) : .caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, style == .primary ? 8 : 6)
            .padding(.horizontal, 8)
            .foregroundStyle(labelColor)
            .background(background)
        }
        .buttonStyle(.plain)
        .disabled(!running)
        .opacity(running ? 1 : 0.72)
        .scaleEffect(hovering && running ? 1.015 : 1)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .background(PointingHandCursor(enabled: running))
        .help(helpText)
        .accessibilityLabel(destination.sendTitle)
    }

    private var labelColor: Color {
        if running {
            return Color(nsColor: .windowBackgroundColor)
        }
        return .secondary
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: style == .primary ? 8 : 7, style: .continuous)
        if running {
            shape.fill(Color.primary.opacity(hovering ? 0.92 : 0.82))
        } else {
            shape
                .fill(Color.primary.opacity(0.05))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
        }
    }

    private var helpText: String {
        if !running {
            return "\(destination.title) is not running"
        }
        if destination.triesComposerFocus {
            return "\(destination.sendTitle). Composer should be focused; Screenshot Shelf will try to find it."
        }
        return "\(destination.sendTitle) — active session"
    }
}

private struct PointingHandCursor: NSViewRepresentable {
    var enabled: Bool

    func makeNSView(context: Context) -> CursorNSView {
        let view = CursorNSView()
        view.cursorEnabled = enabled
        return view
    }

    func updateNSView(_ nsView: CursorNSView, context: Context) {
        nsView.cursorEnabled = enabled
        nsView.window?.invalidateCursorRects(for: nsView)
    }

    final class CursorNSView: NSView {
        var cursorEnabled = true {
            didSet { window?.invalidateCursorRects(for: self) }
        }

        override func resetCursorRects() {
            discardCursorRects()
            guard cursorEnabled, bounds.width > 0, bounds.height > 0 else { return }
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}

private final class MenuTarget: NSObject {
    private static var bag: [MenuTarget] = []
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    static func retain(_ targets: [MenuTarget]) {
        bag.append(contentsOf: targets)
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            bag.removeAll { targets.contains($0) }
        }
    }

    @objc func invoke() {
        handler()
    }
}
