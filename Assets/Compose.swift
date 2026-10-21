import AppKit

// Composes window captures onto a soft gradient backdrop for the README.
// usage: compose <captures dir> <output dir>
let inDir = URL(fileURLWithPath: CommandLine.arguments[1])
let outDir = URL(fileURLWithPath: CommandLine.arguments[2])

func load(_ n: String) -> NSImage? { NSImage(contentsOf: inDir.appendingPathComponent(n)) }

func backdrop(_ size: NSSize) -> NSImage {
    NSImage(size: size, flipped: false) { r in
        NSGradient(colors: [NSColor(srgbRed: 0.90, green: 0.94, blue: 1.0, alpha: 1), NSColor(srgbRed: 0.96, green: 0.92, blue: 1.0, alpha: 1)])!.draw(in: r, angle: -30)
        let blobs: [(NSColor, CGFloat, CGFloat, CGFloat)] = [
            (NSColor(srgbRed: 0.55, green: 0.80, blue: 1.0, alpha: 0.55), 0.1, 0.9, 0.8),
            (NSColor(srgbRed: 0.75, green: 0.70, blue: 1.0, alpha: 0.5), 0.9, 0.8, 0.9),
            (NSColor(srgbRed: 0.60, green: 0.95, blue: 0.90, alpha: 0.45), 0.85, 0.1, 0.8),
            (NSColor(srgbRed: 1.0, green: 0.85, blue: 0.95, alpha: 0.45), 0.15, 0.15, 0.7),
        ]
        for (c, fx, fy, fr) in blobs {
            let rad = max(r.width, r.height) * fr
            let g = NSGradient(colors: [c, c.withAlphaComponent(0)])!
            g.draw(fromCenter: NSPoint(x: r.width * fx, y: r.height * fy), radius: 0, toCenter: NSPoint(x: r.width * fx, y: r.height * fy), radius: rad, options: [])
        }
        return true
    }
}

/// Lays images out in a grid (cols), each drawn at `scale`, with a soft shadow, and saves a JPEG.
func compose(_ names: [String], cols: Int, scale: CGFloat, gap: CGFloat, pad: CGFloat, out: String, shadow: Bool = true) {
    let imgs = names.compactMap(load)
    guard !imgs.isEmpty else { return }
    let sizes = imgs.map { NSSize(width: $0.size.width * scale, height: $0.size.height * scale) }
    let rows = (imgs.count + cols - 1) / cols
    var colW = [CGFloat](repeating: 0, count: cols), rowH = [CGFloat](repeating: 0, count: rows)
    for (i, s) in sizes.enumerated() { colW[i % cols] = max(colW[i % cols], s.width); rowH[i / cols] = max(rowH[i / cols], s.height) }
    let W = pad * 2 + colW.reduce(0, +) + gap * CGFloat(cols - 1)
    let H = pad * 2 + rowH.reduce(0, +) + gap * CGFloat(rows - 1)
    let canvas = NSImage(size: NSSize(width: W, height: H), flipped: false) { r in
        backdrop(r.size).draw(in: r)
        var y = H - pad
        for row in 0..<rows {
            var x = pad
            y -= rowH[row]
            for col in 0..<cols {
                let i = row * cols + col
                guard i < imgs.count else { break }
                let s = sizes[i]
                let rect = NSRect(x: x + (colW[col] - s.width) / 2, y: y + (rowH[row] - s.height) / 2, width: s.width, height: s.height)
                NSGraphicsContext.current?.saveGraphicsState()
                if shadow {
                    let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.22); sh.shadowBlurRadius = 28 * scale; sh.shadowOffset = NSSize(width: 0, height: -14 * scale); sh.set()
                }
                imgs[i].draw(in: rect)
                NSGraphicsContext.current?.restoreGraphicsState()
                x += colW[col] + gap
            }
            y -= gap
        }
        return true
    }
    let rep = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
    try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!.write(to: outDir.appendingPathComponent(out))
    print("wrote \(out) \(Int(W))x\(Int(H))")
}

// Wheel captures include transparent margins; windows include their own shadow, so skip ours there.
compose(["wheel-finder.png", "wheel-convert.png", "wheel-tools.png", "wheel-actions.png"], cols: 4, scale: 0.75, gap: 10, pad: 40, out: "wheels.jpg", shadow: false)
compose(["wheel-finder.png"], cols: 1, scale: 1, gap: 0, pad: 60, out: "hero.jpg", shadow: false)
compose(["editor-add-background.png", "editor-compress.png"], cols: 2, scale: 0.6, gap: 50, pad: 70, out: "editors.jpg", shadow: false)
compose(["settings.png", "welcome.png"], cols: 2, scale: 0.6, gap: 50, pad: 70, out: "windows.jpg", shadow: false)
