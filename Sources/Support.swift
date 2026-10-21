import AppKit
import UniformTypeIdentifiers

struct ConvError: LocalizedError {
    let msg: String
    init(_ m: String) { msg = m }
    var errorDescription: String? { msg }
}

enum FileKind {
    case image, video, audio, pdf, document, markdown, spreadsheet, xlsx, subtitle, archive, folder, other
}

enum Kinds {
    static let image: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tif", "tiff", "bmp", "avif", "svg", "jp2", "psd", "ico", "dng", "cr2", "nef", "arw"]
    static let video: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm", "avi", "wmv", "mpg", "mpeg", "3gp", "mts", "m2ts", "ts"]
    static let audio: Set<String> = ["mp3", "m4a", "aac", "wav", "flac", "aiff", "aif", "ogg", "opus", "wma", "caf", "m4b", "amr"]
    static let document: Set<String> = ["txt", "rtf", "rtfd", "html", "htm", "doc", "docx", "odt", "webarchive", "textclipping"]
    static let markdown: Set<String> = ["md", "markdown"]
    static let spreadsheet: Set<String> = ["csv", "tsv"]
    static let subtitle: Set<String> = ["srt", "vtt"]
    static let archive: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "tbz", "xz", "txz"]

    static func kind(of url: URL) -> FileKind {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
           !["rtfd", "app", "bundle", "textclipping"].contains(url.pathExtension.lowercased()) {
            return .folder
        }
        let e = url.pathExtension.lowercased()
        if image.contains(e) { return .image }
        if video.contains(e) { return .video }
        if audio.contains(e) { return .audio }
        if e == "pdf" { return .pdf }
        if document.contains(e) { return .document }
        if markdown.contains(e) { return .markdown }
        if spreadsheet.contains(e) { return .spreadsheet }
        if e == "xlsx" { return .xlsx }
        if subtitle.contains(e) { return .subtitle }
        if archive.contains(e) { return .archive }
        return .other
    }
}

enum Output {
    /// Destination for a derived file, honoring the output-location preference and never overwriting.
    static func url(for src: URL, ext: String, suffix: String = "") -> URL {
        let dir = Prefs.shared.output.directory ?? src.deletingLastPathComponent()
        let base = src.deletingPathExtension().lastPathComponent + suffix
        var u = dir.appendingPathComponent(base)
        if !ext.isEmpty { u = u.appendingPathExtension(ext) }
        return unique(u)
    }

    static func unique(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var n = 2
        while true {
            var c = dir.appendingPathComponent("\(base) \(n)")
            if !ext.isEmpty { c = c.appendingPathExtension(ext) }
            if !fm.fileExists(atPath: c.path) { return c }
            n += 1
        }
    }

    static func tempDir() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("Clementine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// A unique sibling folder for multi-file outputs (e.g. PDF pages).
    static func folder(for src: URL, suffix: String) -> URL {
        let dir = Prefs.shared.output.directory ?? src.deletingLastPathComponent()
        return unique(dir.appendingPathComponent(src.deletingPathExtension().lastPathComponent + suffix))
    }
}

enum Shell {
    @discardableResult
    static func run(_ exe: String, _ args: [String], cwd: URL? = nil) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            let last = out.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init)
            throw ConvError(last?.isEmpty == false ? last! : "\(URL(fileURLWithPath: exe).lastPathComponent) failed")
        }
        return out
    }
}

extension String {
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

func describeCount(_ urls: [URL], singular: String, plural: String) -> String {
    urls.count == 1 ? singular : plural
}
