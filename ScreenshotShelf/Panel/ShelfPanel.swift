import AppKit

final class ShelfPanel: NSPanel {
    var preferredFrame: NSRect?

    private var isApplyingPreferredFrame = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    convenience init(contentRect: NSRect) {
        self.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .none
        autorecalculatesKeyViewLoop = true
    }

    func applyPreferredFrame(_ frame: NSRect, display: Bool = true) {
        preferredFrame = frame
        isApplyingPreferredFrame = true
        setFrame(frame, display: display)
        isApplyingPreferredFrame = false
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(lockedFrame(from: frameRect), display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        super.setFrame(lockedFrame(from: frameRect), display: displayFlag, animate: false)
    }

    override func setFrameOrigin(_ point: NSPoint) {
        if let preferred = lockedPreferredFrame() {
            super.setFrameOrigin(preferred.origin)
            return
        }
        super.setFrameOrigin(point)
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        if let preferred = lockedPreferredFrame() {
            return preferred
        }
        return super.constrainFrameRect(frameRect, to: screen)
    }

    private func lockedPreferredFrame() -> NSRect? {
        guard !isApplyingPreferredFrame, isVisible, let preferred = preferredFrame else {
            return nil
        }
        return preferred
    }

    private func lockedFrame(from frameRect: NSRect) -> NSRect {
        lockedPreferredFrame() ?? frameRect
    }
}
