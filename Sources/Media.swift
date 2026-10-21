import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

enum Media {
    static func asset(_ url: URL) -> AVURLAsset { AVURLAsset(url: url) }

    static func export(_ source: AVAsset, preset: String, type: AVFileType, to out: URL, range: CMTimeRange? = nil) throws {
        guard let session = AVAssetExportSession(asset: source, presetName: preset) else {
            throw ConvError("This file can't be exported in that format")
        }
        session.outputURL = out
        session.outputFileType = type
        session.shouldOptimizeForNetworkUse = true
        if let range { session.timeRange = range }
        let sem = DispatchSemaphore(value: 0)
        session.exportAsynchronously { sem.signal() }
        sem.wait()
        guard session.status == .completed else {
            throw ConvError(session.error?.localizedDescription ?? "Export failed")
        }
    }

    static func readable(_ url: URL) throws -> AVURLAsset {
        let a = asset(url)
        guard a.isReadable, !a.tracks.isEmpty else {
            throw ConvError("\(url.pathExtension.uppercased()) isn't readable on this Mac")
        }
        return a
    }

    // MARK: video

    static func video(_ urls: [URL], to ext: String) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            if FF.available && (FF.ffmpegOnlyOutputs.contains(ext) || FF.needs(u)) {
                if case .files(let f) = try FF.convert([u], to: ext) { outs += f }
                continue
            }
            let a = try readable(u)
            let out = Output.url(for: u, ext: ext)
            let type: AVFileType = ext == "mov" ? .mov : .mp4
            try export(a, preset: AVAssetExportPresetHighestQuality, type: type, to: out)
            outs.append(out)
        }
        return .files(outs)
    }

    static func compressVideo(_ urls: [URL]) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            if FF.available && FF.needs(u) {
                if case .files(let f) = try FF.convert([u], to: "mp4", suffix: " Compressed", extra: ["-crf", "28", "-vf", "scale='min(1280,iw)':-2"]) { outs += f }
                continue
            }
            let a = try readable(u)
            let out = Output.url(for: u, ext: "mp4", suffix: " Compressed")
            let size = a.tracks(withMediaType: .video).first?.naturalSize ?? CGSize(width: 1920, height: 1080)
            let preset = max(size.width, size.height) > 1300 ? AVAssetExportPreset1280x720 : AVAssetExportPresetMediumQuality
            try export(a, preset: preset, type: .mp4, to: out)
            outs.append(out)
        }
        return .files(outs)
    }

    static func mute(_ urls: [URL]) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            if FF.available && FF.needs(u) {
                if case .files(let f) = try FF.convert([u], to: "mp4", suffix: " Muted", extra: ["-an"]) { outs += f }
                continue
            }
            let a = try readable(u)
            guard let vt = a.tracks(withMediaType: .video).first else { throw ConvError("No video track in \(u.lastPathComponent)") }
            let comp = AVMutableComposition()
            guard let ct = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw ConvError("Compose failed") }
            try ct.insertTimeRange(CMTimeRange(start: .zero, duration: a.duration), of: vt, at: .zero)
            ct.preferredTransform = vt.preferredTransform
            let out = Output.url(for: u, ext: "mp4", suffix: " Muted")
            try export(comp, preset: AVAssetExportPresetHighestQuality, type: .mp4, to: out)
            outs.append(out)
        }
        return .files(outs)
    }

    static func trim(_ urls: [URL], seconds: Double) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            if FF.available && FF.needs(u) {
                let isVideo = Kinds.kind(of: u) == .video
                if case .files(let f) = try FF.convert([u], to: isVideo ? "mp4" : "m4a", suffix: " Trimmed", extra: ["-t", "\(Int(seconds))"]) { outs += f }
                continue
            }
            let a = try readable(u)
            let isVideo = !a.tracks(withMediaType: .video).isEmpty
            let dur = min(CMTimeGetSeconds(a.duration), seconds)
            let range = CMTimeRange(start: .zero, duration: CMTime(seconds: dur, preferredTimescale: 600))
            let out = Output.url(for: u, ext: isVideo ? "mp4" : "m4a", suffix: " Trimmed")
            try export(a, preset: isVideo ? AVAssetExportPresetHighestQuality : AVAssetExportPresetAppleM4A,
                       type: isVideo ? .mp4 : .m4a, to: out, range: range)
            outs.append(out)
        }
        return .files(outs)
    }

    static func thumbnail(_ urls: [URL]) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            if FF.available && FF.needs(u) {
                let out = Output.url(for: u, ext: "jpg", suffix: " Thumbnail")
                try FF.run(["-ss", "1", "-i", u.path, "-frames:v", "1", "-q:v", "2", out.path])
                outs.append(out)
                continue
            }
            let a = try readable(u)
            let gen = AVAssetImageGenerator(asset: a)
            gen.appliesPreferredTrackTransform = true
            let t = CMTime(seconds: min(1, CMTimeGetSeconds(a.duration) / 2), preferredTimescale: 600)
            let cg = try gen.copyCGImage(at: t, actualTime: nil)
            let out = Output.url(for: u, ext: "jpg", suffix: " Thumbnail")
            try Img.write(cg, to: out, type: .jpeg, quality: 0.9)
            outs.append(out)
        }
        return .files(outs)
    }

    static func gif(_ urls: [URL]) throws -> Outcome {
        if FF.available { return try FF.convert(urls, to: "gif") }
        var outs: [URL] = []
        for u in urls {
            let a = try readable(u)
            let gen = AVAssetImageGenerator(asset: a)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 540, height: 540)
            gen.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
            gen.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
            let dur = min(CMTimeGetSeconds(a.duration), 15)
            let fps = 10.0
            let frames = Int(dur * fps)
            guard frames > 0 else { throw ConvError("Video is too short") }
            let out = Output.url(for: u, ext: "gif")
            guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, frames, nil) else { throw ConvError("Can't write GIF") }
            CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / fps]] as CFDictionary
            for i in 0..<frames {
                let t = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
                if let cg = try? gen.copyCGImage(at: t, actualTime: nil) {
                    CGImageDestinationAddImage(dest, cg, frameProps)
                }
            }
            guard CGImageDestinationFinalize(dest) else { throw ConvError("Can't write GIF") }
            outs.append(out)
        }
        return .files(outs)
    }

    // MARK: audio

    struct AudioFormat { let title: String; let ext: String; let args: [String] }
    static var audioFormats: [AudioFormat] {
        var list = nativeAudioFormats
        if FF.available {
            list.insert(AudioFormat(title: "MP3", ext: "mp3", args: []), at: 1)
            list.append(AudioFormat(title: "OGG", ext: "ogg", args: []))
            list.append(AudioFormat(title: "OPUS", ext: "opus", args: []))
        }
        return list
    }
    static let nativeAudioFormats: [AudioFormat] = [
        AudioFormat(title: "M4A", ext: "m4a", args: ["-f", "m4af", "-d", "aac", "-b", "192000"]),
        AudioFormat(title: "WAV", ext: "wav", args: ["-f", "WAVE", "-d", "LEI16"]),
        AudioFormat(title: "AIFF", ext: "aiff", args: ["-f", "AIFF", "-d", "BEI16"]),
        AudioFormat(title: "FLAC", ext: "flac", args: ["-f", "flac", "-d", "flac"]),
        AudioFormat(title: "CAF", ext: "caf", args: ["-f", "caff", "-d", "LEI24"]),
    ]

    /// Audio sources afconvert can't open (or video containers) go through an AAC intermediate first.
    private static func audioSource(_ u: URL) throws -> URL {
        let kind = Kinds.kind(of: u)
        let e = u.pathExtension.lowercased()
        let needsIntermediate = kind == .video || ["ogg", "opus", "wma", "amr"].contains(e)
        guard needsIntermediate else { return u }
        let a = try readable(u)
        guard !a.tracks(withMediaType: .audio).isEmpty else { throw ConvError("No audio track in \(u.lastPathComponent)") }
        let tmp = try Output.tempDir().appendingPathComponent("audio.m4a")
        try export(a, preset: AVAssetExportPresetAppleM4A, type: .m4a, to: tmp)
        return tmp
    }

    static func audio(_ urls: [URL], to f: AudioFormat, suffix: String = "", extraArgs: [String] = []) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            if FF.available && (FF.ffmpegOnlyOutputs.contains(f.ext) || FF.needs(u)) {
                // Translate the afconvert-style extras into ffmpeg ones.
                var extra: [String] = []
                if let i = extraArgs.firstIndex(of: "-b"), i + 1 < extraArgs.count, let bps = Int(extraArgs[i + 1]) { extra += ["-b:a", "\(bps / 1000)k"] }
                if let i = extraArgs.firstIndex(of: "-c"), i + 1 < extraArgs.count { extra += ["-ac", extraArgs[i + 1]] }
                if case .files(let out) = try FF.convert([u], to: f.ext, suffix: suffix, extra: extra) { outs += out }
                continue
            }
            let src = try audioSource(u)
            let out = Output.url(for: u, ext: f.ext, suffix: suffix)
            try Shell.run("/usr/bin/afconvert", f.args + extraArgs + [src.path, out.path])
            outs.append(out)
        }
        return .files(outs)
    }

    static func extractAudio(_ urls: [URL]) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            if FF.available && FF.needs(u) {
                if case .files(let f) = try FF.convert([u], to: "m4a") { outs += f }
                continue
            }
            let a = try readable(u)
            guard !a.tracks(withMediaType: .audio).isEmpty else { throw ConvError("No audio track in \(u.lastPathComponent)") }
            let out = Output.url(for: u, ext: "m4a")
            try export(a, preset: AVAssetExportPresetAppleM4A, type: .m4a, to: out)
            outs.append(out)
        }
        return .files(outs)
    }
}
