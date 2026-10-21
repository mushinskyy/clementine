import AppKit

// Draws the app icon: a sliced clementine on a soft rounded square, at every size iconutil needs.
let outDir = CommandLine.arguments[1]
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Background: macOS-style rounded square with a warm gradient
    let inset = s * 0.08
    let bg = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset), xRadius: s * 0.19, yRadius: s * 0.19)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    NSColor(srgbRed: 1.0, green: 0.96, blue: 0.90, alpha: 1).setFill(); bg.fill()
    ctx.restoreGState()
    ctx.saveGState(); bg.addClip()
    let grad = NSGradient(colors: [NSColor(srgbRed: 1.0, green: 0.97, blue: 0.92, alpha: 1), NSColor(srgbRed: 1.0, green: 0.90, blue: 0.80, alpha: 1)])!
    grad.draw(in: bg.bounds, angle: -70)
    ctx.restoreGState()

    // Fruit
    let c = NSPoint(x: s / 2, y: s / 2 - s * 0.01)
    let r = s * 0.30
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.02), blur: s * 0.05, color: NSColor(srgbRed: 0.9, green: 0.3, blue: 0.1, alpha: 0.35).cgColor)
    let fruit = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    NSColor(srgbRed: 0.98, green: 0.42, blue: 0.14, alpha: 1).setFill(); fruit.fill()
    ctx.restoreGState()
    ctx.saveGState(); fruit.addClip()
    NSGradient(colors: [NSColor(srgbRed: 1.0, green: 0.58, blue: 0.22, alpha: 1), NSColor(srgbRed: 0.95, green: 0.33, blue: 0.10, alpha: 1)])!.draw(in: fruit.bounds, angle: -60)
    ctx.restoreGState()

    // Segments
    NSColor(srgbRed: 1.0, green: 0.92, blue: 0.82, alpha: 0.95).setStroke()
    let inner = r * 0.86
    for i in 0..<5 {
        let a = CGFloat(i) * .pi / 5 + .pi / 10
        let p = NSBezierPath()
        p.move(to: NSPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
        p.line(to: NSPoint(x: c.x - cos(a) * inner, y: c.y - sin(a) * inner))
        p.lineWidth = max(1, s * 0.022)
        p.lineCapStyle = .round
        p.stroke()
    }
    let ring = NSBezierPath(ovalIn: NSRect(x: c.x - inner, y: c.y - inner, width: 2 * inner, height: 2 * inner))
    ring.lineWidth = max(1, s * 0.022); ring.stroke()
    NSColor(srgbRed: 1.0, green: 0.92, blue: 0.82, alpha: 0.95).setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - s * 0.035, y: c.y - s * 0.035, width: s * 0.07, height: s * 0.07)).fill()

    // Leaf
    let leaf = NSBezierPath()
    let lx = c.x + r * 0.35, ly = c.y + r * 0.92
    leaf.move(to: NSPoint(x: lx, y: ly))
    leaf.curve(to: NSPoint(x: lx + s * 0.16, y: ly + s * 0.12), controlPoint1: NSPoint(x: lx + s * 0.02, y: ly + s * 0.11), controlPoint2: NSPoint(x: lx + s * 0.10, y: ly + s * 0.14))
    leaf.curve(to: NSPoint(x: lx, y: ly), controlPoint1: NSPoint(x: lx + s * 0.14, y: ly + s * 0.02), controlPoint2: NSPoint(x: lx + s * 0.06, y: ly - s * 0.01))
    leaf.close()
    NSColor(srgbRed: 0.33, green: 0.65, blue: 0.30, alpha: 1).setFill(); leaf.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in sizes {
    try! draw(px).write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("icons written")
