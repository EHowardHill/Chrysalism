import AppKit
import CoreGraphics

// White raindrop on black, macOS "rounded-square" style.
// The raindrop is the exact SF Symbol ("drop.fill") that Chrysalism uses in
// its menu bar item, rendered white and composited over a black squircle.
// Regenerate with:
//   swift Chrysalism/Scripts/mkicon.swift Chrysalism/Assets.xcassets/AppIcon.appiconset

/// Renders the SF Symbol black-on-transparent, then tints it white with a
/// source-atop fill — the standard AppKit tint recipe — and returns the
/// resulting image.
private func whiteSymbol(named name: String, height: CGFloat) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: 96, weight: .regular)
    let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
    let symbol = base.withSymbolConfiguration(config)!

    let aspect = symbol.size.width / symbol.size.height
    let rect = NSRect(
        x: 0,
        y: 0,
        width: height * aspect,
        height: height
    )

    let canvas = NSImage(size: rect.size)
    canvas.lockFocus()
    symbol.draw(in: rect, from: NSRect(origin: .zero, size: symbol.size), operation: .sourceOver, fraction: 1)
    // White lands only where the symbol painted; transparency stays.
    NSColor.white.setFill()
    NSRect(origin: .zero, size: rect.size).fill(using: .sourceAtop)
    canvas.unlockFocus()
    return canvas
}

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return rep }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    let s = size
    // Black rounded-rect background (macOS squircle).
    let squircle = NSBezierPath(
        roundedRect: NSRect(x: 0, y: 0, width: s, height: s),
        xRadius: s * 0.2245,
        yRadius: s * 0.2245
    )
    NSColor.black.setFill()
    squircle.fill()

    // The drop, sized and centered like a typical macOS app icon glyph.
    let drop = whiteSymbol(named: "drop.fill", height: s * 0.62)
    let dropRect = NSRect(
        x: (s - drop.size.width) / 2,
        y: (s - drop.size.height) / 2,
        width: drop.size.width,
        height: drop.size.height
    )
    drop.draw(in: dropRect)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let sizes: [(String, CGFloat, CGFloat)] = [
    ("icon_16x16", 16, 1), ("icon_16x16@2x", 16, 2),
    ("icon_32x32", 32, 1), ("icon_32x32@2x", 32, 2),
    ("icon_128x128", 128, 1), ("icon_128x128@2x", 128, 2),
    ("icon_256x256", 256, 1), ("icon_256x256@2x", 256, 2),
    ("icon_512x512", 512, 1), ("icon_512x512@2x", 512, 2),
]

let outDir = CommandLine.arguments[1]
for (name, base, scale) in sizes {
    let rep = drawIcon(size: base * CGFloat(scale))
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("icons written")
