import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let screenshotShelfDragDidBegin = Notification.Name("pl.mendrela.screenshotshelf.dragDidBegin")
    static let screenshotShelfDragDidEnd = Notification.Name("pl.mendrela.screenshotshelf.dragDidEnd")
}

struct FileDragView: NSViewRepresentable {
    let fileURL: URL
    let preview: NSImage?
    let onClick: () -> Void
    let onCopy: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void
    var makeSendMenu: (() -> NSMenu)?

    func makeNSView(context: Context) -> FileDragNSView {
        let view = FileDragNSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: FileDragNSView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: FileDragNSView) {
        view.fileURL = fileURL
        view.preview = preview
        view.onClick = onClick
        view.onCopy = onCopy
        view.onReveal = onReveal
        view.onDelete = onDelete
        view.makeSendMenu = makeSendMenu
    }
}

final class FileDragNSView: NSView, NSDraggingSource {
    var fileURL: URL?
    var preview: NSImage?
    var onClick: (() -> Void)?
    var onCopy: (() -> Void)?
    var onReveal: (() -> Void)?
    var onDelete: (() -> Void)?
    var makeSendMenu: (() -> NSMenu)?

    private var mouseDownPoint: NSPoint?
    private var didStartDrag = false

    override var intrinsicContentSize: NSSize { .zero }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let fileURL, let start = mouseDownPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        let distance = hypot(current.x - start.x, current.y - start.y)
        guard distance > 4, !didStartDrag else { return }

        didStartDrag = true
        let draggingItem = NSDraggingItem(pasteboardWriter: ScreenshotDragWriter(url: fileURL))
        let image = preview ?? NSImage(contentsOf: fileURL)
        draggingItem.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !didStartDrag {
            onClick?()
        }
        mouseDownPoint = nil
        didStartDrag = false
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(copyImage(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Reveal in Finder", action: #selector(revealInFinder(_:)), keyEquivalent: "")
        if let sendMenu = makeSendMenu?(), sendMenu.items.isEmpty == false {
            let sendItem = NSMenuItem(title: "Send to", action: nil, keyEquivalent: "")
            sendItem.submenu = sendMenu
            menu.addItem(sendItem)
        }
        menu.addItem(NSMenuItem.separator())
        let trash = NSMenuItem(title: "Move to Trash", action: #selector(moveToTrash(_:)), keyEquivalent: "")
        menu.addItem(trash)
        for item in menu.items where item.action != nil && item.target == nil {
            item.target = self
        }
        return menu
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        NotificationCenter.default.post(name: .screenshotShelfDragDidBegin, object: nil)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        NotificationCenter.default.post(name: .screenshotShelfDragDidEnd, object: nil)
    }

    @objc private func copyImage(_ sender: Any?) {
        onCopy?()
    }

    @objc private func revealInFinder(_ sender: Any?) {
        onReveal?()
    }

    @objc private func moveToTrash(_ sender: Any?) {
        onDelete?()
    }
}

/// Writes the original file URL onto the pasteboard (Finder / Slack / Cursor).
/// Also keeps an in-place NSItemProvider so consumers that ask for the file UTI
/// receive the existing file, not a bitmap-only promised copy.
final class ScreenshotDragWriter: NSObject, NSPasteboardWriting {
    private let url: URL
    private let provider: NSItemProvider

    init(url: URL) {
        self.url = url
        let provider = NSItemProvider()
        let utType = UTType(filenameExtension: url.pathExtension) ?? .image
        provider.registerFileRepresentation(for: utType, visibility: .all, openInPlace: true) { completion in
            completion(url, true, nil)
            return nil
        }
        provider.registerObject(url as NSURL, visibility: .all)
        self.provider = provider
        super.init()
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types = (url as NSURL).writableTypes(for: pasteboard)
        if !types.contains(.fileURL) {
            types.insert(.fileURL, at: 0)
        }
        return types
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type == .fileURL {
            return (url as NSURL).absoluteString
        }
        return (url as NSURL).pasteboardPropertyList(forType: type)
    }
}

