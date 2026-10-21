import Foundation

/// ffmpeg bundled inside the app (Contents/Resources/ffmpeg), with Homebrew as a fallback.
enum FF {
    static let path: String? = {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("ffmpeg").path,
            "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg",
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()
    static var available: Bool { path != nil }

    /// Filled in by `warmUp()`; never computed inside a view body (it runs a process).
    private(set) static var version: String?

    static func warmUp(sync: Bool = false) {
        let work = {
            guard let p = path, let out = try? Shell.run(p, ["-version"]) else { return }
            let line = out.split(separator: "\n").first.map(String.init)
            DispatchQueue.main.async { version = line }
        }
        if sync { work(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) } else { DispatchQueue.global(qos: .utility).async(execute: work) }
    }

    /// Extensions AVFoundation can't open but ffmpeg can.
    static let ffmpegOnlyInputs: Set<String> = ["mkv", "webm", "avi", "wmv", "ogg", "opus", "wma", "flv", "mpg", "mpeg", "ts", "m2ts", "mts", "3gp", "amr", "ogv", "vob", "rm", "asf"]
    /// Output extensions only ffmpeg can write.
    static let ffmpegOnlyOutputs: Set<String> = ["mkv", "webm", "avi", "mp3", "ogg", "opus"]

    static func needs(_ url: URL) -> Bool { ffmpegOnlyInputs.contains(url.pathExtension.lowercased()) }

    static func run(_ args: [String]) throws {
        guard let p = path else { throw ConvError("This conversion needs ffmpeg, which isn't installed") }
        try Shell.run(p, ["-hide_banner", "-loglevel", "error", "-nostdin", "-y"] + args)
    }

    static func codecArgs(for ext: String) -> [String] {
        switch ext {
        case "mp4", "m4v": return ["-c:v", "libx264", "-preset", "fast", "-crf", "20", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
        case "mov": return ["-c:v", "libx264", "-preset", "fast", "-crf", "20", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k"]
        case "mkv": return ["-c:v", "libx264", "-preset", "fast", "-crf", "20", "-c:a", "aac", "-b:a", "192k"]
        case "webm": return ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-row-mt", "1", "-c:a", "libopus", "-b:a", "128k"]
        case "avi": return ["-c:v", "mpeg4", "-q:v", "4", "-c:a", "libmp3lame", "-q:a", "3"]
        case "gif": return ["-vf", "fps=12,scale='min(540,iw)':-2:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse", "-loop", "0"]
        case "mp3": return ["-vn", "-c:a", "libmp3lame", "-q:a", "2"]
        case "m4a": return ["-vn", "-c:a", "aac", "-b:a", "192k"]
        case "wav": return ["-vn", "-c:a", "pcm_s16le"]
        case "aiff": return ["-vn", "-c:a", "pcm_s16be"]
        case "flac": return ["-vn", "-c:a", "flac"]
        case "ogg": return ["-vn", "-c:a", "libvorbis", "-q:a", "5"]
        case "opus": return ["-vn", "-c:a", "libopus", "-b:a", "128k"]
        case "caf": return ["-vn", "-c:a", "pcm_s24le"]
        default: return []
        }
    }

    static func convert(_ urls: [URL], to ext: String, suffix: String = "", extra: [String] = []) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            let out = Output.url(for: u, ext: ext, suffix: suffix)
            var args = ["-i", u.path] + codecArgs(for: ext) + extra
            if ext == "gif" { args += ["-t", "15"] }
            try run(args + [out.path])
            outs.append(out)
        }
        return .files(outs)
    }
}
