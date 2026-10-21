import AppKit
import ImageIO
import PDFKit
import CoreImage
import Vision
import UniformTypeIdentifiers

enum Img {
    static let writable: Set<String> = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
    static func canWrite(_ t: UTType) -> Bool { writable.contains(t.identifier) }

    struct Format {
        let title: String
        let ext: String
        let type: UTType
    }

    /// Output formats offered on the convert wheel, in the order the real app lists them.
    static var formats: [Format] {
        var all: [Format] = [
            Format(title: "PNG", ext: "png", type: .png),
            Format(title: "JPG", ext: "jpg", type: .jpeg),
            Format(title: "WEBP", ext: "webp", type: .webP),
            Format(title: "HEIC", ext: "heic", type: .heic),
            Format(title: "TIFF", ext: "tiff", type: .tiff),
            Format(title: "AVIF", ext: "avif", type: UTType("public.avif") ?? .png),
            Format(title: "BMP", ext: "bmp", type: .bmp),
            Format(title: "GIF", ext: "gif", type: .gif),
            Format(title: "PDF", ext: "pdf", type: .pdf),
        ]
        all = all.filter { $0.type == .pdf || canWrite($0.type) || ($0.ext == "webp" && FF.available) }
        return all
    }

    static func load(_ url: URL) throws -> CGImage {
        let ext = url.pathExtension.lowercased()
        if ext == "svg" || ext == "pdf" {
            guard let ns = NSImage(contentsOf: url) else { throw ConvError("Can't read \(url.lastPathComponent)") }
            return try rasterize(ns, scale: ext == "svg" ? 3 : 2)
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw ConvError("Can't read \(url.lastPathComponent)") }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 30000,
            kCGImageSourceShouldCache: false,
        ]
        if let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) { return img }
        if let img = CGImageSourceCreateImageAtIndex(src, 0, nil) { return img }
        throw ConvError("Unsupported image: \(url.lastPathComponent)")
    }

    static func properties(_ url: URL) -> [CFString: Any] {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return [:] }
        return p
    }

    static func rasterize(_ ns: NSImage, scale: CGFloat = 2) throws -> CGImage {
        let size = ns.size
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw ConvError("Can't rasterize image") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        ns.draw(in: NSRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        NSGraphicsContext.restoreGraphicsState()
        guard let out = ctx.makeImage() else { throw ConvError("Can't rasterize image") }
        return out
    }

    static func hasAlpha(_ img: CGImage) -> Bool {
        switch img.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    /// Draw into a fresh RGBA bitmap of the given pixel size.
    static func draw(width: Int, height: Int, _ body: (CGContext) -> Void) throws -> CGImage {
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw ConvError("Can't create image") }
        body(ctx)
        guard let out = ctx.makeImage() else { throw ConvError("Can't create image") }
        return out
    }

    static func flatten(_ img: CGImage, on color: CGColor = NSColor.white.cgColor) throws -> CGImage {
        try draw(width: img.width, height: img.height) { ctx in
            ctx.setFillColor(color)
            ctx.fill(CGRect(x: 0, y: 0, width: img.width, height: img.height))
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        }
    }

    static func resized(_ img: CGImage, maxPixel: CGFloat) throws -> CGImage {
        let w = CGFloat(img.width), h = CGFloat(img.height)
        let s = min(1, maxPixel / max(w, h))
        if s >= 1 { return img }
        let nw = Int(w * s), nh = Int(h * s)
        return try draw(width: nw, height: nh) { ctx in
            ctx.interpolationQuality = .high
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        }
    }

    static func scaled(_ img: CGImage, by factor: CGFloat) throws -> CGImage {
        let nw = max(1, Int(CGFloat(img.width) * factor)), nh = max(1, Int(CGFloat(img.height) * factor))
        return try draw(width: nw, height: nh) { ctx in
            ctx.interpolationQuality = .high
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        }
    }

    static func write(_ img: CGImage, to url: URL, type: UTType, quality: Double = 0.9, extra: [CFString: Any] = [:]) throws {
        var image = img
        if (type == .jpeg || type == .bmp) && hasAlpha(img) { image = try flatten(img) }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConvError("This Mac can't write \(type.preferredFilenameExtension?.uppercased() ?? "that format")")
        }
        var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        props.merge(extra) { $1 }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ConvError("Failed to write \(url.lastPathComponent)") }
    }

    /// Format to use when a tool should keep the source's format but must re-encode.
    static func nativeType(for url: URL) -> (UTType, String) {
        let e = url.pathExtension.lowercased()
        switch e {
        case "jpg", "jpeg": return (.jpeg, "jpg")
        case "heic", "heif": return canWrite(.heic) ? (.heic, "heic") : (.jpeg, "jpg")
        case "tif", "tiff": return (.tiff, "tiff")
        case "bmp": return (.bmp, "bmp")
        case "gif": return (.gif, "gif")
        case "webp": return canWrite(.webP) ? (.webP, "webp") : (.png, "png")
        default: return (.png, "png")
        }
    }

    // MARK: conversions

    static func convert(_ urls: [URL], to f: Format) throws -> Outcome {
        if f.type == .pdf { return .files(try urls.map { try toPDF([$0]) }) }   // one PDF per image
        var outs: [URL] = []
        for u in urls {
            if f.ext == "webp" && !canWrite(.webP) {
                let out = Output.url(for: u, ext: "webp")
                let tmp = try Output.tempDir().appendingPathComponent("in.png")
                try write(try load(u), to: tmp, type: .png)
                try FF.run(["-i", tmp.path, "-c:v", "libwebp", "-quality", "90", out.path])
                outs.append(out)
                continue
            }
            let img = try load(u)
            let out = Output.url(for: u, ext: f.ext)
            try write(img, to: out, type: f.type, quality: 0.92)
            outs.append(out)
        }
        return .files(outs)
    }

    static func toPDF(_ urls: [URL]) throws -> URL {
        let doc = PDFDocument()
        for (i, u) in urls.enumerated() {
            let cg = try load(u)
            // 300 DPI pages
            let pts = NSSize(width: CGFloat(cg.width) * 72 / 300, height: CGFloat(cg.height) * 72 / 300)
            let ns = NSImage(cgImage: cg, size: pts)
            guard let page = PDFPage(image: ns) else { throw ConvError("Can't add \(u.lastPathComponent) to PDF") }
            doc.insert(page, at: i)
        }
        let out = Output.url(for: urls[0], ext: "pdf", suffix: urls.count > 1 ? " and \(urls.count - 1) more" : "")
        guard doc.write(to: out) else { throw ConvError("Couldn't write PDF") }
        return out
    }

    // MARK: tools

    static func compress(_ urls: [URL], quality: Double, maxPixel: CGFloat) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            var img = try load(u)
            img = try resized(img, maxPixel: maxPixel)
            let e = u.pathExtension.lowercased()
            let useHEIC = (e == "heic" || e == "heif") && canWrite(.heic)
            let out = Output.url(for: u, ext: useHEIC ? "heic" : "jpg", suffix: " Compressed")
            try write(img, to: out, type: useHEIC ? .heic : .jpeg, quality: quality)
            outs.append(out)
        }
        return .files(outs)
    }

    static func resize(_ urls: [URL], factor: CGFloat?, maxPixel: CGFloat?) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            var img = try load(u)
            if let factor { img = try scaled(img, by: factor) }
            if let maxPixel { img = try resized(img, maxPixel: maxPixel) }
            let (t, ext) = nativeType(for: u)
            let suffix = factor != nil ? " \(Int((factor ?? 1) * 100))%" : " \(img.width)px"
            let out = Output.url(for: u, ext: ext, suffix: suffix)
            try write(img, to: out, type: t)
            outs.append(out)
        }
        return .files(outs)
    }

    static func crop(_ img: CGImage, aspect: CGFloat?, size: CGSize?) throws -> CGImage {
        var rect = CGRect(x: 0, y: 0, width: img.width, height: img.height)
        if let aspect {
            let w = CGFloat(img.width), h = CGFloat(img.height)
            if w / h > aspect { let nw = h * aspect; rect = CGRect(x: (w - nw) / 2, y: 0, width: nw, height: h) }
            else { let nh = w / aspect; rect = CGRect(x: 0, y: (h - nh) / 2, width: w, height: nh) }
        }
        guard let cropped = img.cropping(to: rect.integral) else { throw ConvError("Crop failed") }
        if let size, size.width > 0, size.height > 0 {
            return try draw(width: Int(size.width), height: Int(size.height)) { ctx in
                ctx.interpolationQuality = .high
                ctx.draw(cropped, in: CGRect(origin: .zero, size: size))
            }
        }
        return cropped
    }

    static func rotate(_ urls: [URL]) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            let img = try load(u)
            let rotated = try draw(width: img.height, height: img.width) { ctx in
                ctx.translateBy(x: CGFloat(img.height), y: 0)
                ctx.rotate(by: -.pi / 2)
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
            }
            let (t, ext) = nativeType(for: u)
            let out = Output.url(for: u, ext: ext, suffix: " Rotated")
            try write(rotated, to: out, type: t)
            outs.append(out)
        }
        return .files(outs)
    }

    static func stripMetadata(_ urls: [URL]) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            guard let src = CGImageSourceCreateWithURL(u as CFURL, nil),
                  let type = CGImageSourceGetType(src) else { throw ConvError("Can't read \(u.lastPathComponent)") }
            let out = Output.url(for: u, ext: u.pathExtension, suffix: " Clean")
            guard let dest = CGImageDestinationCreateWithURL(out as CFURL, type, 1, nil) else { throw ConvError("Can't write \(u.lastPathComponent)") }
            let props = properties(u)
            var opts: [CFString: Any] = [
                kCGImagePropertyExifDictionary: kCFNull,
                kCGImagePropertyGPSDictionary: kCFNull,
                kCGImagePropertyIPTCDictionary: kCFNull,
                kCGImagePropertyTIFFDictionary: kCFNull,
                kCGImagePropertyExifAuxDictionary: kCFNull,
                kCGImagePropertyMakerAppleDictionary: kCFNull,
                kCGImageMetadataShouldExcludeXMP: true,
                kCGImageMetadataShouldExcludeGPS: true,
            ]
            if let o = props[kCGImagePropertyOrientation] { opts[kCGImagePropertyOrientation] = o }
            var err: Unmanaged<CFError>?
            if !CGImageDestinationCopyImageSource(dest, src, opts as CFDictionary, &err) {
                // Fallback: full re-encode without properties.
                let img = try load(u)
                let (t, ext) = nativeType(for: u)
                let out2 = Output.url(for: u, ext: ext, suffix: " Clean")
                try write(img, to: out2, type: t, quality: 0.95)
                outs.append(out2)
                try? FileManager.default.removeItem(at: out)
                continue
            }
            outs.append(out)
        }
        return .files(outs)
    }

    static func grayscale(_ urls: [URL]) throws -> Outcome {
        var outs: [URL] = []
        let ctx = CIContext()
        for u in urls {
            let img = try load(u)
            let ci = CIImage(cgImage: img)
            guard let f = CIFilter(name: "CIPhotoEffectMono") else { throw ConvError("Filter unavailable") }
            f.setValue(ci, forKey: kCIInputImageKey)
            guard let outCI = f.outputImage, let cg = ctx.createCGImage(outCI, from: outCI.extent) else { throw ConvError("Filter failed") }
            let (t, ext) = nativeType(for: u)
            let out = Output.url(for: u, ext: ext, suffix: " Mono")
            try write(cg, to: out, type: t)
            outs.append(out)
        }
        return .files(outs)
    }

    /// Detect faces (and, failing that, text) and cover them.
    static func redact(_ urls: [URL]) throws -> Outcome {
        var outs: [URL] = []
        var total = 0
        for u in urls {
            let img = try load(u)
            var boxes: [CGRect] = []
            let faces = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: img, options: [:])
            try handler.perform([faces])
            boxes = (faces.results ?? []).map { $0.boundingBox }
            if boxes.isEmpty {
                let text = VNRecognizeTextRequest()
                text.recognitionLevel = .fast
                try VNImageRequestHandler(cgImage: img, options: [:]).perform([text])
                boxes = (text.results ?? []).map { $0.boundingBox }
            }
            guard !boxes.isEmpty else { continue }
            total += boxes.count
            let w = CGFloat(img.width), h = CGFloat(img.height)
            let out = try draw(width: img.width, height: img.height) { ctx in
                ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
                ctx.setFillColor(NSColor(white: 0.1, alpha: 1).cgColor)
                for b in boxes {
                    var r = CGRect(x: b.minX * w, y: b.minY * h, width: b.width * w, height: b.height * h)
                    r = r.insetBy(dx: -r.width * 0.15, dy: -r.height * 0.2)
                    ctx.fill(r)
                }
            }
            let (t, ext) = nativeType(for: u)
            let dest = Output.url(for: u, ext: ext, suffix: " Redacted")
            try write(out, to: dest, type: t)
            outs.append(dest)
        }
        if outs.isEmpty { return .message("No faces or text found to redact") }
        return .files(outs)
    }

    static func collage(_ urls: [URL]) throws -> Outcome {
        guard urls.count >= 2 else { throw ConvError("Select at least two images for a collage") }
        let imgs = try urls.map { try resized(try load($0), maxPixel: 1200) }
        let cols = Int(ceil(sqrt(Double(imgs.count))))
        let rows = Int(ceil(Double(imgs.count) / Double(cols)))
        let cell: CGFloat = 800, gap: CGFloat = 24
        let W = Int(CGFloat(cols) * cell + CGFloat(cols + 1) * gap)
        let H = Int(CGFloat(rows) * cell + CGFloat(rows + 1) * gap)
        let out = try draw(width: W, height: H) { ctx in
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            ctx.interpolationQuality = .high
            for (i, im) in imgs.enumerated() {
                let c = i % cols, r = i / cols
                let x = gap + CGFloat(c) * (cell + gap)
                let y = CGFloat(H) - gap - CGFloat(r + 1) * cell - CGFloat(r) * gap
                let s = min(cell / CGFloat(im.width), cell / CGFloat(im.height))
                let dw = CGFloat(im.width) * s, dh = CGFloat(im.height) * s
                let rect = CGRect(x: x + (cell - dw) / 2, y: y + (cell - dh) / 2, width: dw, height: dh)
                let path = CGPath(roundedRect: rect, cornerWidth: 24, cornerHeight: 24, transform: nil)
                ctx.saveGState(); ctx.addPath(path); ctx.clip()
                ctx.draw(im, in: rect)
                ctx.restoreGState()
            }
        }
        let dest = Output.url(for: urls[0], ext: "jpg", suffix: " Collage")
        try write(out, to: dest, type: .jpeg, quality: 0.9)
        return .files([dest])
    }
}
