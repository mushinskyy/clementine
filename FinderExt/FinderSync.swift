import AppKit
import FinderSync

/// Finder Sync extension: adds a "Clementine" submenu to Finder's context menu and a
/// toolbar button. It never touches files itself; it hands the selection to the app
/// through the clementine:// URL scheme.
class FinderSync: FIFinderSync {
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override var toolbarItemName: String { "Clementine" }
    override var toolbarItemToolTip: String { "Convert or process the selected files with Clementine" }
    override var toolbarItemImage: NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let r = rect.insetBy(dx: 2, dy: 2)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: r).fill()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSColor.black.setStroke()
            let c = NSPoint(x: rect.midX, y: rect.midY)
            for i in 0..<4 {
                let a = CGFloat(i) * .pi / 4
                let p = NSBezierPath()
                p.move(to: NSPoint(x: c.x + cos(a) * 6.2, y: c.y + sin(a) * 6.2))
                p.line(to: NSPoint(x: c.x - cos(a) * 6.2, y: c.y - sin(a) * 6.2))
                p.lineWidth = 1.4
                p.stroke()
            }
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSBezierPath(ovalIn: NSRect(x: c.x - 1.6, y: c.y - 1.6, width: 3.2, height: 3.2)).fill()
            return true
        }
        img.isTemplate = true
        return img
    }

    // MARK: menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let ctl = FIFinderSyncController.default()
        var urls = ctl.selectedItemURLs() ?? []
        if urls.isEmpty, menuKind == .toolbarItemMenu, let t = ctl.targetedURL() { urls = [t] }
        guard !urls.isEmpty else { return nil }

        let sub = NSMenu(title: "Clementine")
        sub.addItem(item("Convert or process…", wheel: "pick", title: "", urls: urls))
        sub.addItem(.separator())

        let kinds = Set(urls.map(Catalog.kind(of:)))
        let common = kinds.count == 1 ? kinds.first! : Catalog.Kind.other
        let multi = urls.count > 1
        let exts = Set(urls.map { $0.pathExtension.lowercased() })

        let converts = Catalog.converts(common).filter { !(urls.count == 1 && exts.contains($0.lowercased())) || $0.contains(".") }
        for t in converts { sub.addItem(item("Convert to \(t)", wheel: "convert", title: t, urls: urls)) }
        if common == .archive { sub.addItem(item("Extract", wheel: "convert", title: "Extract", urls: urls)) }
        sub.addItem(item("ZIP", wheel: "convert", title: "ZIP", urls: urls))

        let tools = Catalog.tools(common, multi: multi)
        if !tools.isEmpty {
            sub.addItem(.separator())
            for t in tools { sub.addItem(item(t, wheel: "tools", title: t, urls: urls)) }
        }

        sub.addItem(.separator())
        for t in ["AirDrop", "Float", "Copy Path", "Move", "Terminal"] {
            sub.addItem(item(t, wheel: "actions", title: t, urls: urls))
        }

        let menu = NSMenu(title: "")
        let root = NSMenuItem(title: "Clementine", action: nil, keyEquivalent: "")
        root.submenu = sub
        menu.addItem(root)
        return menu
    }

    private func item(_ label: String, wheel: String, title: String, urls: [URL]) -> NSMenuItem {
        let m = NSMenuItem(title: label, action: #selector(run(_:)), keyEquivalent: "")
        m.target = self
        m.representedObject = ["wheel": wheel, "item": title, "paths": urls.map(\.path)] as [String: Any]
        return m
    }

    @objc private func run(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let wheel = info["wheel"] as? String, let title = info["item"] as? String,
              let paths = info["paths"] as? [String] else { return }
        var c = URLComponents()
        c.scheme = "clementine"
        c.host = wheel == "pick" ? "pick" : "run"
        var q = [URLQueryItem(name: "wheel", value: wheel), URLQueryItem(name: "item", value: title)]
        q += paths.map { URLQueryItem(name: "path", value: $0) }
        c.queryItems = q
        guard let url = c.url else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Mirror of the app's option catalog (titles must match the app's wheel items).
enum Catalog {
    enum Kind { case image, video, audio, pdf, document, spreadsheet, subtitle, archive, folder, other }

    static let image: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "avif", "svg", "jp2", "psd", "ico", "dng", "cr2", "nef", "arw"]
    static let video: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm", "avi", "wmv", "mpg", "mpeg", "3gp", "mts", "m2ts", "ts"]
    static let audio: Set<String> = ["mp3", "m4a", "aac", "wav", "flac", "aiff", "aif", "ogg", "opus", "wma", "caf", "m4b", "amr"]
    static let document: Set<String> = ["txt", "rtf", "rtfd", "html", "htm", "doc", "docx", "odt", "webarchive", "md", "markdown"]
    static let spreadsheet: Set<String> = ["csv", "tsv", "xlsx"]
    static let subtitle: Set<String> = ["srt", "vtt"]
    static let archive: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "tbz", "xz", "txz"]

    static func kind(of url: URL) -> Kind {
        let e = url.pathExtension.lowercased()
        if url.hasDirectoryPath && !["rtfd", "app"].contains(e) { return .folder }
        if image.contains(e) { return .image }
        if video.contains(e) { return .video }
        if audio.contains(e) { return .audio }
        if e == "pdf" { return .pdf }
        if document.contains(e) { return .document }
        if spreadsheet.contains(e) { return .spreadsheet }
        if subtitle.contains(e) { return .subtitle }
        if archive.contains(e) { return .archive }
        return .other
    }

    static func converts(_ k: Kind) -> [String] {
        switch k {
        case .image: return ["PNG", "JPG", "WEBP", "HEIC", "TIFF", "AVIF", "BMP", "GIF", "PDF"]
        case .video: return ["MP4", "MOV", "MKV", "WEBM", "GIF", "M4A", "MP3", "WAV"]
        case .audio: return ["M4A", "MP3", "WAV", "AIFF", "FLAC", "OGG", "OPUS"]
        case .pdf: return ["PNG", "JPG", "TXT", "DOCX", "RTF", "HTML"]
        case .document: return ["PDF", "DOCX", "TXT", "RTF", "HTML", "ODT", "MD"]
        case .spreadsheet: return ["XLSX", "CSV", "TSV", "JSON", "HTML", "MD"]
        case .subtitle: return ["SRT", "VTT", "TXT"]
        case .archive, .folder, .other: return []
        }
    }

    static func tools(_ k: Kind, multi: Bool) -> [String] {
        switch k {
        case .image: return ["Compress", "Add BG", "Crop", "Redact", "Metadata", "Resize", "Rotate", "Mono"] + (multi ? ["One PDF", "Collage"] : [])
        case .video: return ["Compress", "Mute", "Trim", "Thumbnail", "Audio"]
        case .audio: return ["Compress", "Trim", "Mono"]
        case .pdf: return (multi ? ["Merge"] : []) + ["Split", "Compress", "Rotate", "Text", "Images", "Count"]
        case .document: return ["Text", "Count", "PDF"]
        case .spreadsheet: return ["Count"]
        case .subtitle: return []
        case .archive: return ["Extract"]
        case .folder, .other: return ["Duplicate"]
        }
    }
}
