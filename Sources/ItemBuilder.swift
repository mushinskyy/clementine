import AppKit
import UniformTypeIdentifiers

enum ItemBuilder {
    static func items(for kind: WheelKind, urls: [URL], folder: URL? = nil) -> [WheelItem] {
        if kind == .finder { return FinderActions.items(urls: urls, folder: folder) }
        guard !urls.isEmpty else { return [] }
        let kinds = Set(urls.map(Kinds.kind(of:)))
        let common: FileKind? = kinds.count == 1 ? kinds.first : nil
        switch kind {
        case .finder: return []
        case .convert: return convert(common, urls: urls)
        case .tools: return tools(common, urls: urls)
        case .actions: return actions()
        }
    }

    // MARK: Convert

    private static func convert(_ kind: FileKind?, urls: [URL]) -> [WheelItem] {
        var out: [WheelItem] = []
        let exts = Set(urls.map { $0.pathExtension.lowercased() })
        func skip(_ ext: String, _ aliases: [String] = []) -> Bool {
            urls.count == 1 && (exts.contains(ext) || !exts.isDisjoint(with: aliases))
        }
        switch kind {
        case .image:
            for f in Img.formats {
                if skip(f.ext, f.ext == "jpg" ? ["jpeg"] : f.ext == "tiff" ? ["tif"] : f.ext == "heic" ? ["heif"] : []) { continue }
                let caption = f.ext == "pdf" && urls.count > 1 ? "Convert each image to its own PDF" : "Convert to \(f.title)"
                out.append(WheelItem(f.title, caption) { try Img.convert($0, to: f) })
            }
        case .video:
            if !skip("mp4") { out.append(WheelItem("MP4", "Convert to MP4") { try Media.video($0, to: "mp4") }) }
            if !skip("mov") { out.append(WheelItem("MOV", "Convert to MOV") { try Media.video($0, to: "mov") }) }
            if FF.available {
                if !skip("mkv") { out.append(WheelItem("MKV", "Convert to MKV") { try Media.video($0, to: "mkv") }) }
                if !skip("webm") { out.append(WheelItem("WEBM", "Convert to WebM (VP9)") { try Media.video($0, to: "webm") }) }
            }
            out.append(WheelItem("GIF", "Convert to animated GIF (first 15 s)") { try Media.gif($0) })
            out.append(WheelItem("M4A", "Extract audio as M4A") { try Media.extractAudio($0) })
            for f in Media.audioFormats where f.ext != "m4a" {
                out.append(WheelItem(f.title, "Extract audio as \(f.title)") { try Media.audio($0, to: f) })
            }
        case .audio:
            for f in Media.audioFormats where !skip(f.ext, f.ext == "aiff" ? ["aif"] : []) {
                out.append(WheelItem(f.title, "Convert to \(f.title)") { try Media.audio($0, to: f) })
            }
        case .pdf:
            out.append(WheelItem("PNG", "Render pages as PNG at 300 DPI") { try PDFC.toImages($0, type: .png, ext: "png") })
            out.append(WheelItem("JPG", "Render pages as JPG at 300 DPI") { try PDFC.toImages($0, type: .jpeg, ext: "jpg") })
            out.append(WheelItem("TXT", "Extract text to TXT") { try PDFC.toText($0) })
            out.append(WheelItem("DOCX", "Convert text to DOCX") { try PDFC.toDocument($0, fmt: "docx", ext: "docx") })
            out.append(WheelItem("RTF", "Convert text to RTF") { try PDFC.toDocument($0, fmt: "rtf", ext: "rtf") })
            out.append(WheelItem("HTML", "Convert text to HTML") { try PDFC.toDocument($0, fmt: "html", ext: "html") })
            out.append(WheelItem("HEIC", "Render pages as HEIC") { try PDFC.toImages($0, type: .heic, ext: "heic") })
            out.append(WheelItem("TIFF", "Render pages as TIFF") { try PDFC.toImages($0, type: .tiff, ext: "tiff") })
        case .document, .markdown:
            for f in Doc.formats where !skip(f.ext, f.ext == "html" ? ["htm"] : f.ext == "md" ? ["markdown"] : []) {
                out.append(WheelItem(f.title, "Convert to \(f.title)") { try Doc.convert($0, to: f) })
            }
        case .spreadsheet, .xlsx:
            let targets = [("XLSX", "xlsx"), ("CSV", "csv"), ("TSV", "tsv"), ("JSON", "json"), ("HTML", "html"), ("MD", "md")]
            for (t, e) in targets where !skip(e) {
                out.append(WheelItem(t, "Convert to \(t)") { try Sheet.convert($0, to: e) })
            }
        case .subtitle:
            if !skip("srt") { out.append(WheelItem("SRT", "Convert to SRT") { try Subs.convert($0, to: "srt") }) }
            if !skip("vtt") { out.append(WheelItem("VTT", "Convert to VTT") { try Subs.convert($0, to: "vtt") }) }
            out.append(WheelItem("TXT", "Plain text without timings") { try Subs.convert($0, to: "txt") })
        case .archive:
            out.append(WheelItem("Extract", "Extract into a folder", symbol: "shippingbox.and.arrow.backward") { try Arch.extract($0) })
        default:
            break
        }
        if kind != .archive {
            out.append(WheelItem("ZIP", "Compress into a ZIP archive") { try Arch.zip($0) })
            out.append(WheelItem("TAR", "Pack into a TAR archive") { try Arch.tar($0, gzip: false) })
            out.append(WheelItem("TAR.GZ", "Pack into a gzipped TAR archive") { try Arch.tar($0, gzip: true) })
        }
        return out
    }

    // MARK: Tools

    private static func tools(_ kind: FileKind?, urls: [URL]) -> [WheelItem] {
        var out: [WheelItem] = []
        let multi = urls.count > 1
        switch kind {
        case .image:
            out.append(WheelItem("Compress", "Compress images", symbol: "arrow.down.right.and.arrow.up.left", onMain: true) { try Editors.open("compress", urls: $0) })
            out.append(WheelItem("Metadata", "Remove EXIF, GPS and XMP metadata", symbol: "tag") { try Img.stripMetadata($0) })
            out.append(WheelItem("Add BG", "Place on a color or gradient background", symbol: "photo.on.rectangle", onMain: true) { try Editors.open("bg", urls: $0) })
            out.append(WheelItem("Crop", "Crop to an aspect ratio or exact size", symbol: "crop", onMain: true) { try Editors.open("crop", urls: $0) })
            out.append(WheelItem("Redact", "Cover faces (or text) with a solid color", symbol: "eye.slash") { try Img.redact($0) })
            out.append(WheelItem("Resize", "Resize to 50%", symbol: "arrow.up.left.and.arrow.down.right") { try Img.resize($0, factor: 0.5, maxPixel: nil) })
            out.append(WheelItem("Rotate", "Rotate 90° clockwise", symbol: "rotate.right") { try Img.rotate($0) })
            out.append(WheelItem("Mono", "Convert to black and white", symbol: "circle.lefthalf.filled") { try Img.grayscale($0) })
            if multi {
                out.append(WheelItem("One PDF", "Combine all images into one PDF", symbol: "doc.richtext") { .files([try Img.toPDF($0)]) })
                out.append(WheelItem("Collage", "Combine images in a grid", symbol: "square.grid.2x2") { try Img.collage($0) })
            }
        case .video:
            out.append(WheelItem("Compress", "Compress to a smaller MP4", symbol: "arrow.down.right.and.arrow.up.left") { try Media.compressVideo($0) })
            out.append(WheelItem("Mute", "Remove the audio track", symbol: "speaker.slash") { try Media.mute($0) })
            out.append(WheelItem("Trim", "Keep the first 30 seconds", symbol: "scissors") { try Media.trim($0, seconds: 30) })
            out.append(WheelItem("Thumbnail", "Save a frame as JPG", symbol: "photo") { try Media.thumbnail($0) })
            out.append(WheelItem("Audio", "Extract audio as M4A", symbol: "waveform") { try Media.extractAudio($0) })
            out.append(WheelItem("GIF", "Make an animated GIF", symbol: "film") { try Media.gif($0) })
        case .audio:
            out.append(WheelItem("Compress", "Compress to 64 kbps AAC", symbol: "arrow.down.right.and.arrow.up.left") { try Media.audio($0, to: Media.audioFormats[0], suffix: " Compressed", extraArgs: ["-b", "64000"]) })
            out.append(WheelItem("Trim", "Keep the first 30 seconds", symbol: "scissors") { try Media.trim($0, seconds: 30) })
            out.append(WheelItem("Mono", "Mix down to mono", symbol: "speaker.wave.1") { try Media.audio($0, to: Media.audioFormats[0], suffix: " Mono", extraArgs: ["-c", "1"]) })
        case .pdf:
            if multi { out.append(WheelItem("Merge", "Merge into one PDF", symbol: "doc.on.doc") { try PDFC.merge($0) }) }
            out.append(WheelItem("Split", "Split into one PDF per page", symbol: "square.split.2x1") { try PDFC.split($0) })
            out.append(WheelItem("Compress", "Shrink images inside the PDF", symbol: "arrow.down.right.and.arrow.up.left") { try PDFC.compress($0) })
            out.append(WheelItem("Rotate", "Rotate all pages 90°", symbol: "rotate.right") { try PDFC.rotate($0) })
            out.append(WheelItem("Text", "Extract text to TXT", symbol: "text.alignleft") { try PDFC.toText($0) })
            out.append(WheelItem("Images", "Render pages as JPG", symbol: "photo.stack") { try PDFC.toImages($0, type: .jpeg, ext: "jpg") })
            out.append(WheelItem("Count", "Count words and characters", symbol: "number") { try Doc.wordCount($0) })
        case .document, .markdown:
            out.append(WheelItem("Text", "Save as plain text", symbol: "text.alignleft") { try Doc.plainText($0) })
            out.append(WheelItem("Count", "Count words and characters", symbol: "number") { try Doc.wordCount($0) })
            out.append(WheelItem("PDF", "Export as PDF", symbol: "doc.richtext") { try Doc.convert($0, to: Doc.formats[0]) })
        case .spreadsheet, .xlsx:
            out.append(WheelItem("Count", "Count rows and columns", symbol: "number") { urls in
                let rows = try Sheet.read(urls[0])
                return .message("\(rows.count) rows · \(rows.map(\.count).max() ?? 0) columns")
            })
        case .archive:
            out.append(WheelItem("Extract", "Extract into a folder", symbol: "shippingbox.and.arrow.backward") { try Arch.extract($0) })
        default:
            break
        }
        if kind != .archive {
            out.append(WheelItem("ZIP", "Compress into a ZIP archive", symbol: "doc.zipper") { try Arch.zip($0) })
        }
        out.append(WheelItem("Duplicate", "Duplicate next to the original", symbol: "plus.square.on.square") { try Actions.duplicate($0) })
        return out
    }

    // MARK: Actions

    private static func actions() -> [WheelItem] {
        [
            WheelItem("AirDrop", "Share through AirDrop", symbol: "airplayaudio", onMain: true) { try Actions.airdrop($0) },
            WheelItem("Float", "Keep in a floating shelf", symbol: "rectangle.stack", onMain: true) { try Actions.float($0) },
            WheelItem("Copy", "Copy to the clipboard", symbol: "doc.on.clipboard", onMain: true) { try Actions.copy($0) },
            WheelItem("Move", "Move to a folder you choose", symbol: "folder", onMain: true) { try Actions.move($0) },
            WheelItem("Copy Path", "Copy the full path as text", symbol: "text.quote", onMain: true) { try Actions.copyPath($0) },
            WheelItem("Terminal", "Open the folder in Terminal", symbol: "terminal", onMain: true) { try Actions.terminal($0) },
        ]
    }
}
