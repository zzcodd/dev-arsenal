// Generates a placeholder Resources/AppIcon.png (1024x1024): a rounded gradient
// squircle with a white gauge glyph. Run once to verify the icon pipeline:
//   swift scripts/gen-placeholder-icon.swift
// Then replace Resources/AppIcon.png with your own design and rebuild.
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Rounded "squircle" with transparent margin (macOS icons carry their own shape).
let margin = size * 0.09
let rect = NSRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
let radius = rect.width * 0.22
let clip = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
clip.addClip()

// Diagonal gradient background.
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.20, green: 0.47, blue: 0.96, alpha: 1),
    NSColor(srgbRed: 0.46, green: 0.24, blue: 0.86, alpha: 1),
])!
gradient.draw(in: rect, angle: -90)

// White gauge glyph, centered.
let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .semibold)
if let base = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {
    let glyph = NSImage(size: base.size)
    glyph.lockFocus()
    base.draw(in: NSRect(origin: .zero, size: base.size))
    NSColor.white.set()
    NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
    glyph.unlockFocus()
    let p = NSRect(x: (size - base.size.width) / 2,
                   y: (size - base.size.height) / 2,
                   width: base.size.width, height: base.size.height)
    glyph.draw(in: p)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to render png\n".data(using: .utf8)!)
    exit(1)
}
let url = URL(fileURLWithPath: "Resources/AppIcon.png")
try! png.write(to: url)
print("wrote \(url.path)")
