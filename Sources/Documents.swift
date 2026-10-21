import AppKit
import PDFKit
import UniformTypeIdentifiers

enum Doc {
    struct Format { let title: String; let ext: String; let textutil: String? }
    static let formats: [Format] = [
        Format(title: "PDF", ext: "pdf", textutil: nil),
        Format(title: "DOCX", ext: "docx", textutil: "docx"),
        Format(title: "TXT", ext: "txt", textutil: "txt"),
        Format(title: "RTF", ext: "rtf", textutil: "rtf"),
        Format(title: "HTML", ext: "html", textutil: "html"),
        Format(title: "ODT", ext: "odt", textutil: "odt"),
        Format(title: "DOC", ext: "doc", textutil: "doc"),
        Format(title: "MD", ext: "md", textutil: nil),
    ]

    /// Markdown sources are turned into HTML first so textutil can read them.
    private static func textutilSource(_ u: URL) throws -> URL {
        guard Kinds.kind(of: u) == .markdown else { return u }
        let text = try String(contentsOf: u, encoding: .utf8)
        let html = MiniMarkdown.html(text, title: u.deletingPathExtension().lastPathComponent)
        let tmp = try Output.tempDir().appendingPathComponent(u.deletingPathExtension().lastPathComponent + ".html")
        try html.write(to: tmp, atomically: true, encoding: .utf8)
        return tmp
    }

    static func convert(_ urls: [URL], to f: Format) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            switch f.ext {
            case "pdf": outs.append(try toPDF(u))
            case "md": outs.append(try toMarkdown(u))
            default:
                let src = try textutilSource(u)
                let out = Output.url(for: u, ext: f.ext)
                try Shell.run("/usr/bin/textutil", ["-convert", f.textutil ?? f.ext, "-output", out.path, src.path])
                outs.append(out)
            }
        }
        return .files(outs)
    }

    static func attributed(_ u: URL) throws -> NSAttributedString {
        let e = u.pathExtension.lowercased()
        var src = u
        if ["html", "htm", "md", "markdown", "webarchive"].contains(e) {
            // Avoid WebKit-based HTML import off the main thread: go through RTF.
            let html = try textutilSource(u)
            let tmp = try Output.tempDir().appendingPathComponent("doc.rtf")
            try Shell.run("/usr/bin/textutil", ["-convert", "rtf", "-output", tmp.path, html.path])
            src = tmp
        }
        var attrs: NSDictionary?
        let s = try NSAttributedString(url: src, options: [:], documentAttributes: &attrs)
        return s
    }

    static func toPDF(_ u: URL) throws -> URL {
        let text = try attributed(u)
        let out = Output.url(for: u, ext: "pdf")
        try writePDF(text, to: out)
        return out
    }

    static func toMarkdown(_ u: URL) throws -> URL {
        let text = try attributed(u)
        let out = Output.url(for: u, ext: "md")
        try MiniMarkdown.markdown(from: text).write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    /// Paginate attributed text onto US Letter pages.
    static func writePDF(_ text: NSAttributedString, to out: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let inset: CGFloat = 60
        let storage = NSTextStorage(attributedString: text)
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        guard let ctx = CGContext(out as CFURL, mediaBox: &mediaBox, nil) else { throw ConvError("Can't create PDF") }
        var glyph = 0
        var pages = 0
        while glyph < lm.numberOfGlyphs || pages == 0 {
            let tc = NSTextContainer(size: CGSize(width: 612 - 2 * inset, height: 792 - 2 * inset))
            tc.lineFragmentPadding = 0
            lm.addTextContainer(tc)
            let range = lm.glyphRange(for: tc)
            ctx.beginPDFPage(nil)
            ctx.saveGState()
            ctx.translateBy(x: 0, y: 792)
            ctx.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            lm.drawBackground(forGlyphRange: range, at: CGPoint(x: inset, y: inset))
            lm.drawGlyphs(forGlyphRange: range, at: CGPoint(x: inset, y: inset))
            NSGraphicsContext.restoreGraphicsState()
            ctx.restoreGState()
            ctx.endPDFPage()
            pages += 1
            if range.length == 0 { break }
            glyph = NSMaxRange(range)
            if pages > 2000 { break }
        }
        ctx.closePDF()
    }

    static func wordCount(_ urls: [URL]) throws -> Outcome {
        var words = 0, chars = 0
        for u in urls {
            let s: String
            if Kinds.kind(of: u) == .pdf { s = PDFDocument(url: u)?.string ?? "" } else { s = try attributed(u).string }
            words += s.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            chars += s.count
        }
        let f = NumberFormatter(); f.numberStyle = .decimal
        return .message("\(f.string(from: words as NSNumber) ?? "\(words)") words · \(f.string(from: chars as NSNumber) ?? "\(chars)") characters")
    }

    static func plainText(_ urls: [URL]) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            let s: String
            if Kinds.kind(of: u) == .pdf { s = PDFDocument(url: u)?.string ?? "" } else { s = try attributed(u).string }
            let out = Output.url(for: u, ext: "txt")
            try s.write(to: out, atomically: true, encoding: .utf8)
            outs.append(out)
        }
        return .files(outs)
    }
}

// MARK: - PDF

enum PDFC {
    static func load(_ u: URL) throws -> PDFDocument {
        guard let d = PDFDocument(url: u) else { throw ConvError("Can't open \(u.lastPathComponent)") }
        if d.isLocked { throw ConvError("\(u.lastPathComponent) is password protected") }
        return d
    }

    static func render(_ page: PDFPage, dpi: CGFloat) throws -> CGImage {
        let b = page.bounds(for: .mediaBox)
        let s = dpi / 72
        let w = Int(b.width * s), h = Int(b.height * s)
        return try Img.draw(width: w, height: h) { ctx in
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.saveGState()
            ctx.scaleBy(x: s, y: s)
            ctx.translateBy(x: -b.minX, y: -b.minY)
            page.draw(with: .mediaBox, to: ctx)
            ctx.restoreGState()
        }
    }

    static func toImages(_ urls: [URL], type: UTType, ext: String, dpi: CGFloat = 300) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            let d = try load(u)
            if d.pageCount == 1, let p = d.page(at: 0) {
                let out = Output.url(for: u, ext: ext)
                try Img.write(try render(p, dpi: dpi), to: out, type: type, quality: 0.92)
                outs.append(out)
                continue
            }
            let folder = Output.folder(for: u, suffix: " Pages")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let base = u.deletingPathExtension().lastPathComponent
            for i in 0..<d.pageCount {
                guard let p = d.page(at: i) else { continue }
                let out = folder.appendingPathComponent(String(format: "%@ %03d.%@", base, i + 1, ext))
                try Img.write(try render(p, dpi: dpi), to: out, type: type, quality: 0.92)
            }
            outs.append(folder)
        }
        return .files(outs)
    }

    static func toText(_ urls: [URL]) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            let d = try load(u)
            let out = Output.url(for: u, ext: "txt")
            try (d.string ?? "").write(to: out, atomically: true, encoding: .utf8)
            outs.append(out)
        }
        return .files(outs)
    }

    /// Text-based conversion to a word-processor format (layout is not preserved).
    static func toDocument(_ urls: [URL], fmt: String, ext: String) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            let d = try load(u)
            let text = NSMutableAttributedString()
            let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12)]
            for i in 0..<d.pageCount {
                guard let p = d.page(at: i) else { continue }
                text.append(NSAttributedString(string: (p.string ?? "") + "\n\n", attributes: body))
            }
            let tmp = try Output.tempDir().appendingPathComponent("doc.rtf")
            let rtf = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            try rtf.write(to: tmp)
            let out = Output.url(for: u, ext: ext)
            try Shell.run("/usr/bin/textutil", ["-convert", fmt, "-output", out.path, tmp.path])
            outs.append(out)
        }
        return .files(outs)
    }

    static func merge(_ urls: [URL]) throws -> Outcome {
        guard urls.count >= 2 else { throw ConvError("Select at least two PDFs to merge") }
        let merged = PDFDocument()
        for u in urls {
            let d = try load(u)
            for i in 0..<d.pageCount { if let p = d.page(at: i) { merged.insert(p, at: merged.pageCount) } }
        }
        let out = Output.url(for: urls[0], ext: "pdf", suffix: " Merged")
        guard merged.write(to: out) else { throw ConvError("Couldn't write merged PDF") }
        return .files([out])
    }

    static func split(_ urls: [URL]) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            let d = try load(u)
            guard d.pageCount > 1 else { throw ConvError("\(u.lastPathComponent) has only one page") }
            let folder = Output.folder(for: u, suffix: " Split")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let base = u.deletingPathExtension().lastPathComponent
            for i in 0..<d.pageCount {
                guard let p = d.page(at: i) else { continue }
                let single = PDFDocument()
                single.insert(p, at: 0)
                single.write(to: folder.appendingPathComponent(String(format: "%@ %03d.pdf", base, i + 1)))
            }
            outs.append(folder)
        }
        return .files(outs)
    }

    static func compress(_ urls: [URL]) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            let d = try load(u)
            let out = Output.url(for: u, ext: "pdf", suffix: " Compressed")
            let origSize = (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int) ?? 0
            var ok = false
            if #available(macOS 13.4, *) {
                ok = d.write(to: out, withOptions: [.optimizeImagesForScreenOption: true, .saveImagesAsJPEGOption: true])
            }
            let newSize = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? Int.max
            if !ok || newSize >= origSize {
                // Fall back to re-rendering pages as JPEGs at 150 DPI.
                let rendered = PDFDocument()
                for i in 0..<d.pageCount {
                    guard let p = d.page(at: i) else { continue }
                    let cg = try render(p, dpi: 150)
                    let tmp = try Output.tempDir().appendingPathComponent("p.jpg")
                    try Img.write(cg, to: tmp, type: .jpeg, quality: 0.6)
                    guard let ns = NSImage(contentsOf: tmp) else { continue }
                    let b = p.bounds(for: .mediaBox)
                    let sized = NSImage(size: b.size)
                    sized.addRepresentation(ns.representations[0])
                    if let page = PDFPage(image: sized) { rendered.insert(page, at: rendered.pageCount) }
                }
                try? FileManager.default.removeItem(at: out)
                guard rendered.write(to: out) else { throw ConvError("Couldn't write compressed PDF") }
                let fallbackSize = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? Int.max
                if fallbackSize >= origSize {
                    try? FileManager.default.removeItem(at: out)
                    return .message("\(u.lastPathComponent) is already as small as it gets")
                }
            }
            outs.append(out)
        }
        return .files(outs)
    }

    static func rotate(_ urls: [URL]) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            let d = try load(u)
            for i in 0..<d.pageCount { d.page(at: i)?.rotation += 90 }
            let out = Output.url(for: u, ext: "pdf", suffix: " Rotated")
            guard d.write(to: out) else { throw ConvError("Couldn't write PDF") }
            outs.append(out)
        }
        return .files(outs)
    }
}

// MARK: - Minimal Markdown

enum MiniMarkdown {
    static func html(_ md: String, title: String) -> String {
        var out = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>\(title.xmlEscaped)</title></head><body>\n"
        var inList: String? = nil
        var inCode = false
        var para: [String] = []
        func flushPara() {
            if !para.isEmpty { out += "<p>\(inline(para.joined(separator: " ")))</p>\n"; para = [] }
        }
        func closeList() { if let l = inList { out += "</\(l)>\n"; inList = nil } }
        for rawLine in md.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                flushPara(); closeList()
                out += inCode ? "</code></pre>\n" : "<pre><code>"
                inCode.toggle(); continue
            }
            if inCode { out += rawLine.xmlEscaped + "\n"; continue }
            if line.isEmpty { flushPara(); closeList(); continue }
            if let h = line.firstIndex(where: { $0 != "#" }), line.hasPrefix("#"), line[h] == " " {
                flushPara(); closeList()
                let level = min(6, line.distance(from: line.startIndex, to: h))
                out += "<h\(level)>\(inline(String(line[h...]).trimmingCharacters(in: .whitespaces)))</h\(level)>\n"; continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flushPara()
                if inList != "ul" { closeList(); out += "<ul>\n"; inList = "ul" }
                out += "<li>\(inline(String(line.dropFirst(2))))</li>\n"; continue
            }
            if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty, line[line.index(after: dot)...].hasPrefix(" ") {
                flushPara()
                if inList != "ol" { closeList(); out += "<ol>\n"; inList = "ol" }
                out += "<li>\(inline(String(line[line.index(after: dot)...]).trimmingCharacters(in: .whitespaces)))</li>\n"; continue
            }
            if line.hasPrefix("> ") { flushPara(); closeList(); out += "<blockquote><p>\(inline(String(line.dropFirst(2))))</p></blockquote>\n"; continue }
            if line == "---" || line == "***" { flushPara(); closeList(); out += "<hr>\n"; continue }
            para.append(line)
        }
        flushPara(); closeList()
        if inCode { out += "</code></pre>\n" }
        return out + "</body></html>"
    }

    private static func inline(_ s: String) -> String {
        var t = s.xmlEscaped
        t = regex(t, "`([^`]+)`", "<code>$1</code>")
        t = regex(t, "\\*\\*(.+?)\\*\\*", "<b>$1</b>")
        t = regex(t, "__(.+?)__", "<b>$1</b>")
        t = regex(t, "\\*(.+?)\\*", "<i>$1</i>")
        t = regex(t, "_(.+?)_", "<i>$1</i>")
        t = regex(t, "!\\[([^\\]]*)\\]\\(([^)]+)\\)", "<img alt=\"$1\" src=\"$2\">")
        t = regex(t, "\\[([^\\]]+)\\]\\(([^)]+)\\)", "<a href=\"$2\">$1</a>")
        return t
    }

    private static func regex(_ s: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    /// Very small rich-text → Markdown: headings by font size, bold/italic by traits, paragraphs.
    static func markdown(from text: NSAttributedString) -> String {
        var out = ""
        let str = text.string as NSString
        var paraStart = 0
        while paraStart < str.length {
            let pr = str.paragraphRange(for: NSRange(location: paraStart, length: 0))
            var line = ""
            var headingSize: CGFloat = 0
            text.enumerateAttributes(in: pr, options: []) { attrs, r, _ in
                var piece = str.substring(with: r).replacingOccurrences(of: "\n", with: "")
                if piece.isEmpty { return }
                if let f = attrs[.font] as? NSFont {
                    let traits = f.fontDescriptor.symbolicTraits
                    if f.pointSize >= 16 { headingSize = max(headingSize, f.pointSize) }
                    else {
                        if traits.contains(.bold) { piece = "**\(piece)**" }
                        if traits.contains(.italic) { piece = "*\(piece)*" }
                    }
                }
                line += piece
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                if headingSize >= 24 { out += "# \(trimmed)\n\n" }
                else if headingSize >= 18 { out += "## \(trimmed)\n\n" }
                else if headingSize >= 16 { out += "### \(trimmed)\n\n" }
                else { out += "\(trimmed)\n\n" }
            }
            paraStart = NSMaxRange(pr)
            if pr.length == 0 { break }
        }
        return out
    }
}
