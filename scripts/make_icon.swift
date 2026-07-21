// Renders the Cadence app icon: sleek graphite squircle with a bold white
// closing-quote mark (an "utterance"). Run: swift scripts/make_icon.swift <output-1024.png>
import AppKit

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "cadence-1024.png"

let canvas = CGFloat(1024)
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

// Standard macOS icon grid: 824×824 squircle centered on 1024 canvas.
let inset = (canvas - 824) / 2
let squircle = NSBezierPath(
    roundedRect: NSRect(x: inset, y: inset, width: 824, height: 824),
    xRadius: 186, yRadius: 186)

let gradient = NSGradient(
    starting: NSColor(red: 0.40, green: 0.43, blue: 0.48, alpha: 1),
    ending: NSColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1))!
gradient.draw(in: squircle, angle: -90)

// Soft top glow that fades out — no hard edges.
NSGraphicsContext.current?.saveGraphicsState()
squircle.addClip()
let glow = NSGradient(
    starting: NSColor.white.withAlphaComponent(0.18),
    ending: NSColor.white.withAlphaComponent(0))!
glow.draw(
    in: NSRect(x: inset, y: canvas / 2, width: 824, height: 412 + inset),
    angle: -90)
NSGraphicsContext.current?.restoreGraphicsState()

// Closing quotation mark — what you utter, framed in quotes.
let config = NSImage.SymbolConfiguration(pointSize: 440, weight: .bold)
guard let symbol = NSImage(
        systemSymbolName: "quote.closing", accessibilityDescription: nil)?
    .withSymbolConfiguration(config)
else {
    fatalError("SF Symbol 'quote.closing' unavailable")
}

// Tint the (black) template glyph white by painting over its alpha mask.
let tinted = NSImage(size: symbol.size)
tinted.lockFocus()
symbol.draw(in: NSRect(origin: .zero, size: symbol.size))
NSColor.white.set()
NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
tinted.unlockFocus()

let symbolRect = NSRect(
    x: (canvas - tinted.size.width) / 2,
    y: (canvas - tinted.size.height) / 2,
    width: tinted.size.width, height: tinted.size.height)
tinted.draw(in: symbolRect)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else {
    fatalError("Could not render icon")
}
try! png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
