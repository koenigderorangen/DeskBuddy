import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fatalError("Output PNG path required")
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else { fatalError("No graphics context") }
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let backgroundRect = NSRect(x: 44, y: 44, width: 936, height: 936)
let background = NSBezierPath(roundedRect: backgroundRect, xRadius: 220, yRadius: 220)
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.01, green: 0.24, blue: 0.43, alpha: 1),
    NSColor(srgbRed: 0.00, green: 0.50, blue: 0.78, alpha: 1)
])!
gradient.draw(in: background, angle: -55)

let glassRect = NSRect(x: 86, y: 86, width: 852, height: 852)
let glass = NSBezierPath(roundedRect: glassRect, xRadius: 185, yRadius: 185)
NSColor.white.withAlphaComponent(0.12).setFill()
glass.fill()
NSColor.white.withAlphaComponent(0.24).setStroke()
glass.lineWidth = 3
glass.stroke()

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -16), blur: 34, color: NSColor.black.withAlphaComponent(0.25).cgColor)

let desk = NSBezierPath()
desk.lineWidth = 34
desk.lineCapStyle = .round
desk.lineJoinStyle = .round
desk.appendRoundedRect(NSRect(x: 244, y: 554, width: 536, height: 104), xRadius: 28, yRadius: 28)
desk.move(to: NSPoint(x: 312, y: 552))
desk.line(to: NSPoint(x: 312, y: 340))
desk.move(to: NSPoint(x: 712, y: 552))
desk.line(to: NSPoint(x: 712, y: 340))
desk.move(to: NSPoint(x: 258, y: 334))
desk.line(to: NSPoint(x: 366, y: 334))
desk.move(to: NSPoint(x: 658, y: 334))
desk.line(to: NSPoint(x: 766, y: 334))
NSColor.white.setStroke()
desk.stroke()
context.restoreGState()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon")
}
try png.write(to: outputURL)
