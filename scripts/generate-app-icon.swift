import AppKit

let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

let canvas = 1024.0
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: canvas, height: canvas)
let inset = rect.insetBy(dx: 70, dy: 70)
let path = NSBezierPath(roundedRect: inset, xRadius: 220, yRadius: 220)

NSColor(calibratedRed: 0.18, green: 0.20, blue: 0.24, alpha: 1).setFill()
path.fill()

let shelf = NSBezierPath(roundedRect: NSRect(x: 190, y: 250, width: 644, height: 70), xRadius: 16, yRadius: 16)
NSColor(calibratedRed: 0.62, green: 0.44, blue: 0.28, alpha: 1).setFill()
shelf.fill()
NSColor(calibratedRed: 0.45, green: 0.30, blue: 0.18, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 190, y: 250, width: 644, height: 18)).fill()

func drawFrame(origin: NSPoint, size: NSSize, tilt: CGFloat, fill: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: origin.x + size.width / 2, yBy: origin.y + size.height / 2)
    transform.rotate(byDegrees: tilt)
    transform.translateX(by: -size.width / 2, yBy: -size.height / 2)
    transform.concat()

    let card = NSRect(origin: .zero, size: size)
    NSColor.white.withAlphaComponent(0.96).setFill()
    NSBezierPath(roundedRect: card, xRadius: 28, yRadius: 28).fill()

    let photo = card.insetBy(dx: 36, dy: 48)
    fill.setFill()
    NSBezierPath(roundedRect: photo, xRadius: 16, yRadius: 16).fill()

    NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.28).setFill()
    NSBezierPath(ovalIn: NSRect(x: photo.minX + 28, y: photo.maxY - 90, width: 70, height: 70)).fill()
    NSGraphicsContext.restoreGraphicsState()
}

drawFrame(
    origin: NSPoint(x: 250, y: 360),
    size: NSSize(width: 300, height: 360),
    tilt: -8,
    fill: NSColor(calibratedRed: 0.35, green: 0.55, blue: 0.72, alpha: 1)
)
drawFrame(
    origin: NSPoint(x: 470, y: 380),
    size: NSSize(width: 300, height: 360),
    tilt: 7,
    fill: NSColor(calibratedRed: 0.78, green: 0.52, blue: 0.42, alpha: 1)
)

image.unlockFocus()

let tiff = image.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
let png = rep.representation(using: .png, properties: [:])!
let masterURL = URL(fileURLWithPath: outputDir).appendingPathComponent("AppIcon-1024.png")
try png.write(to: masterURL)
print("Wrote \(masterURL.path)")
