import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Hosts SwiftUI editor sheets in their own windows.
enum EditorHost {
    private static var windows: [NSWindow] = []

    static func present<V: View>(title: String, size: NSSize, _ view: V) {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = title
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: view.environment(\.editorWindow, WindowBox(w)))
        w.center()
        windows.append(w)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            windows.removeAll { $0 == w }
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

final class WindowBox { weak var window: NSWindow?; init(_ w: NSWindow) { window = w } }
private struct EditorWindowKey: EnvironmentKey { static let defaultValue: WindowBox? = nil }
extension EnvironmentValues {
    var editorWindow: WindowBox? {
        get { self[EditorWindowKey.self] }
        set { self[EditorWindowKey.self] = newValue }
    }
}

let accent = Color.accentColor

struct EditorChrome<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }.padding(.top, 8)
            content
            Spacer(minLength: 0)
            HStack { footer }
        }
        .padding(20)
    }
}

struct SaveButton: View {
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Text(label).padding(.horizontal, 8) }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(accent)
    }
}

enum Preview {
    static func image(_ cg: CGImage) -> NSImage { NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }
}

// MARK: - Add Background

enum Background: Equatable {
    case solid(Int)      // index into solids
    case gradient(Int)   // index into gradients

    static let gradients: [[NSColor]] = [
        [NSColor(srgbRed: 0.99, green: 0.55, blue: 0.25, alpha: 1), NSColor(srgbRed: 0.93, green: 0.30, blue: 0.45, alpha: 1), NSColor(srgbRed: 0.45, green: 0.45, blue: 0.95, alpha: 1)],
        [NSColor(srgbRed: 0.35, green: 0.55, blue: 1.0, alpha: 1), NSColor(srgbRed: 0.85, green: 0.45, blue: 1.0, alpha: 1)],
        [NSColor(srgbRed: 1.0, green: 0.85, blue: 0.40, alpha: 1), NSColor(srgbRed: 0.40, green: 0.85, blue: 0.70, alpha: 1), NSColor(srgbRed: 0.45, green: 0.55, blue: 1.0, alpha: 1)],
        [NSColor(srgbRed: 0.96, green: 0.94, blue: 0.92, alpha: 1), NSColor(srgbRed: 0.82, green: 0.84, blue: 0.90, alpha: 1)],
        [NSColor(srgbRed: 1.0, green: 0.70, blue: 0.75, alpha: 1), NSColor(srgbRed: 0.75, green: 0.80, blue: 1.0, alpha: 1)],
        [NSColor(srgbRed: 0.10, green: 0.45, blue: 0.35, alpha: 1), NSColor(srgbRed: 0.65, green: 0.20, blue: 0.55, alpha: 1), NSColor(srgbRed: 0.10, green: 0.15, blue: 0.35, alpha: 1)],
        [NSColor(srgbRed: 0.20, green: 0.55, blue: 0.95, alpha: 1), NSColor(srgbRed: 0.30, green: 0.85, blue: 0.95, alpha: 1)],
        [NSColor(srgbRed: 0.12, green: 0.12, blue: 0.16, alpha: 1), NSColor(srgbRed: 0.30, green: 0.30, blue: 0.40, alpha: 1)],
    ]
    static let solids: [NSColor] = [
        .white,
        NSColor(srgbRed: 0.97, green: 0.80, blue: 0.30, alpha: 1),
        NSColor(srgbRed: 0.55, green: 0.80, blue: 0.30, alpha: 1),
        NSColor(srgbRed: 0.25, green: 0.60, blue: 0.40, alpha: 1),
        NSColor(srgbRed: 0.20, green: 0.55, blue: 0.55, alpha: 1),
        NSColor(srgbRed: 0.35, green: 0.80, blue: 0.85, alpha: 1),
        NSColor(srgbRed: 0.25, green: 0.40, blue: 0.85, alpha: 1),
        NSColor(srgbRed: 0.12, green: 0.14, blue: 0.22, alpha: 1),
        NSColor(srgbRed: 0.55, green: 0.40, blue: 0.85, alpha: 1),
    ]
}

enum Ratio: String, CaseIterable, Identifiable {
    case auto = "Auto", square = "1:1", wide = "16:9", portrait = "4:5", classic = "3:2"
    var id: String { rawValue }
    var value: CGFloat? {
        switch self {
        case .auto: return nil
        case .square: return 1
        case .wide: return 16.0 / 9.0
        case .portrait: return 4.0 / 5.0
        case .classic: return 3.0 / 2.0
        }
    }
}

struct AddBGSettings {
    var background: Background = .gradient(0)
    var padding: CGFloat = 160
    var corners: CGFloat = 24
    var shadow: CGFloat = 24
    var ratio: Ratio = .auto

    func render(_ img: CGImage, scale: CGFloat = 1) throws -> CGImage {
        let p = padding * scale, c = corners * scale, sh = shadow * scale
        let iw = CGFloat(img.width), ih = CGFloat(img.height)
        var cw = iw + 2 * p, ch = ih + 2 * p
        if let r = ratio.value {
            if cw / ch < r { cw = ch * r } else { ch = cw / r }
        }
        let W = Int(cw.rounded()), H = Int(ch.rounded())
        return try Img.draw(width: W, height: H) { ctx in
            let rect = CGRect(x: 0, y: 0, width: W, height: H)
            switch background {
            case .solid(let i):
                ctx.setFillColor(Background.solids[i].cgColor); ctx.fill(rect)
            case .gradient(let i):
                let colors = Background.gradients[i].map(\.cgColor) as CFArray
                let locs = (0..<Background.gradients[i].count).map { CGFloat($0) / CGFloat(max(1, Background.gradients[i].count - 1)) }
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locs) {
                    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(H)), end: CGPoint(x: CGFloat(W), y: 0), options: [])
                }
            }
            let target = CGRect(x: (cw - iw) / 2, y: (ch - ih) / 2, width: iw, height: ih)
            let path = CGPath(roundedRect: target, cornerWidth: min(c, iw / 2), cornerHeight: min(c, ih / 2), transform: nil)
            if sh > 0 {
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: -sh / 2), blur: sh, color: NSColor.black.withAlphaComponent(0.35).cgColor)
                ctx.addPath(path); ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
                ctx.restoreGState()
            }
            ctx.saveGState()
            ctx.addPath(path); ctx.clip()
            ctx.interpolationQuality = .high
            ctx.draw(img, in: target)
            ctx.restoreGState()
        }
    }
}

struct AddBGView: View {
    let urls: [URL]
    let original: CGImage
    let preview: CGImage
    let previewScale: CGFloat
    @State private var s = AddBGSettings()
    @State private var rendered: NSImage?
    @Environment(\.editorWindow) private var window

    init(urls: [URL], image: CGImage) {
        self.urls = urls
        self.original = image
        let p = (try? Img.resized(image, maxPixel: 700)) ?? image
        self.preview = p
        self.previewScale = CGFloat(p.width) / CGFloat(image.width)
    }

    var body: some View {
        EditorChrome(title: "Add a background", subtitle: urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) images") {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08))
                if let r = rendered {
                    Image(nsImage: r).resizable().aspectRatio(contentMode: .fit).padding(10)
                }
            }
            .frame(height: 300)

            Grid(alignment: .leading, verticalSpacing: 12) {
                GridRow {
                    Text("Background").gridColumnAlignment(.leading)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(0..<Background.gradients.count, id: \.self) { i in
                                swatch(.gradient(i)) {
                                    LinearGradient(colors: Background.gradients[i].map { Color($0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                                }
                            }
                        }
                        HStack(spacing: 8) {
                            ForEach(0..<Background.solids.count, id: \.self) { i in
                                swatch(.solid(i)) { Color(Background.solids[i]) }
                            }
                        }
                    }
                }
                slider("Padding", $s.padding, 0...800, unit: "px")
                slider("Corners", $s.corners, 0...300, unit: "px")
                slider("Shadow", $s.shadow, 0...120, unit: "px")
                GridRow {
                    Text("Ratio")
                    Picker("", selection: $s.ratio) {
                        ForEach(Ratio.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 300)
                }
            }
        } footer: {
            Button("Reset") { s = AddBGSettings() }
            Spacer()
            SaveButton(label: "Save with Background") { save() }
        }
        .frame(width: 560, height: 640)
        .onAppear { refresh() }
        .onChange(of: s.background) { _ in refresh() }
        .onChange(of: s.padding) { _ in refresh() }
        .onChange(of: s.corners) { _ in refresh() }
        .onChange(of: s.shadow) { _ in refresh() }
        .onChange(of: s.ratio) { _ in refresh() }
    }

    private func swatch<C: View>(_ bg: Background, @ViewBuilder _ fill: () -> C) -> some View {
        Button { s.background = bg } label: {
            RoundedRectangle(cornerRadius: 7).fill(.clear).frame(width: 26, height: 26)
                .background(fill().clipShape(RoundedRectangle(cornerRadius: 7)))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(s.background == bg ? accent : Color.secondary.opacity(0.3), lineWidth: s.background == bg ? 2.5 : 1))
        }.buttonStyle(.plain)
    }

    private func slider(_ label: String, _ v: Binding<CGFloat>, _ range: ClosedRange<CGFloat>, unit: String) -> some View {
        GridRow {
            Text(label)
            HStack {
                Slider(value: v, in: range).tint(accent)
                Text("\(Int(v.wrappedValue)) \(unit)").monospacedDigit().frame(width: 60, alignment: .trailing).foregroundStyle(.secondary)
            }
        }
    }

    private func refresh() {
        if let cg = try? s.render(preview, scale: previewScale) { rendered = Preview.image(cg) }
    }

    private func save() {
        let settings = s
        let targets = urls
        window?.window?.close()
        Runner.run(WheelItem("Add BG", "Adding a background", symbol: nil) { _ in
            var outs: [URL] = []
            for u in targets {
                let img = try Img.load(u)
                let out = Output.url(for: u, ext: "png", suffix: " With Background")
                try Img.write(try settings.render(img), to: out, type: .png)
                outs.append(out)
            }
            return .files(outs)
        }, urls: targets)
    }
}

// MARK: - Crop

struct CropView: View {
    let urls: [URL]
    let original: CGImage
    let preview: CGImage
    @State private var ratio: Ratio = .square
    @State private var exact = false
    @State private var width = ""
    @State private var height = ""
    @State private var rendered: NSImage?
    @Environment(\.editorWindow) private var window

    init(urls: [URL], image: CGImage) {
        self.urls = urls; self.original = image
        self.preview = (try? Img.resized(image, maxPixel: 700)) ?? image
    }

    var body: some View {
        EditorChrome(title: "Crop", subtitle: urls.count == 1 ? "\(urls[0].lastPathComponent) · \(original.width)×\(original.height)" : "\(urls.count) images") {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08))
                if let r = rendered { Image(nsImage: r).resizable().aspectRatio(contentMode: .fit).padding(10) }
            }.frame(height: 300)
            Grid(alignment: .leading, verticalSpacing: 12) {
                GridRow {
                    Text("Aspect ratio")
                    Picker("", selection: $ratio) { ForEach(Ratio.allCases) { Text($0 == .auto ? "Original" : $0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden()
                }
                GridRow {
                    Toggle("Exact size", isOn: $exact)
                    HStack {
                        TextField("Width", text: $width).frame(width: 80)
                        Text("×")
                        TextField("Height", text: $height).frame(width: 80)
                        Text("px").foregroundStyle(.secondary)
                    }.disabled(!exact)
                }
            }
            Text("Crops from the center. Exact size scales the crop to the given dimensions.").font(.caption).foregroundStyle(.secondary)
        } footer: {
            Spacer()
            SaveButton(label: "Save Cropped") { save() }
        }
        .frame(width: 520, height: 540)
        .onAppear { refresh() }
        .onChange(of: ratio) { _ in refresh() }
        .onChange(of: exact) { _ in refresh() }
        .onChange(of: width) { _ in refresh() }
        .onChange(of: height) { _ in refresh() }
    }

    private var aspect: CGFloat? {
        if exact, let w = Double(width), let h = Double(height), w > 0, h > 0 { return CGFloat(w / h) }
        return ratio.value
    }

    private func refresh() {
        if let cg = try? Img.crop(preview, aspect: aspect, size: nil) { rendered = Preview.image(cg) }
    }

    private func save() {
        let a = aspect
        let size: CGSize? = (exact && Double(width) != nil && Double(height) != nil) ? CGSize(width: Double(width)!, height: Double(height)!) : nil
        let targets = urls
        window?.window?.close()
        Runner.run(WheelItem("Crop", "Cropping", symbol: nil) { _ in
            var outs: [URL] = []
            for u in targets {
                let img = try Img.load(u)
                let (t, ext) = Img.nativeType(for: u)
                let out = Output.url(for: u, ext: ext, suffix: " Cropped")
                try Img.write(try Img.crop(img, aspect: a, size: size), to: out, type: t, quality: 0.92)
                outs.append(out)
            }
            return .files(outs)
        }, urls: targets)
    }
}

// MARK: - Compress

struct CompressView: View {
    let urls: [URL]
    let original: CGImage
    let originalBytes: Int
    @State private var quality: Double = 0.6
    @State private var maxPixel: Int = 2560
    @State private var estimate: Int?
    @State private var estimating = false
    @Environment(\.editorWindow) private var window

    static let sizes: [(String, Int)] = [("Original", 0), ("4096 px", 4096), ("2560 px", 2560), ("1920 px", 1920), ("1280 px", 1280), ("800 px", 800)]

    init(urls: [URL], image: CGImage) {
        self.urls = urls; self.original = image
        self.originalBytes = (try? FileManager.default.attributesOfItem(atPath: urls[0].path)[.size] as? Int) ?? 0
    }

    var body: some View {
        EditorChrome(title: "Compress", subtitle: urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) images") {
            Grid(alignment: .leading, verticalSpacing: 14) {
                GridRow {
                    Text("Quality")
                    HStack {
                        Slider(value: $quality, in: 0.2...1).tint(accent)
                        Text("\(Int(quality * 100))%").monospacedDigit().frame(width: 50, alignment: .trailing).foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("Longest side")
                    Picker("", selection: $maxPixel) {
                        ForEach(CompressView.sizes, id: \.1) { Text($0.0).tag($0.1) }
                    }.labelsHidden().frame(width: 140)
                }
                GridRow {
                    Text("Preset")
                    HStack {
                        Button("Email") { quality = 0.5; maxPixel = 1280 }
                        Button("Web") { quality = 0.7; maxPixel = 1920 }
                        Button("Light") { quality = 0.85; maxPixel = 0 }
                    }
                }
            }
            HStack {
                Text("Original: \(fmt(originalBytes))").foregroundStyle(.secondary)
                Spacer()
                if estimating { ProgressView().controlSize(.small) }
                if let e = estimate {
                    Text("Compressed: \(fmt(e))").fontWeight(.semibold)
                    if originalBytes > 0 { Text("(−\(max(0, 100 - e * 100 / originalBytes))%)").foregroundStyle(.secondary) }
                }
            }
            .font(.callout)
            Text("Saves as JPEG (or HEIC for HEIC sources) next to the original.").font(.caption).foregroundStyle(.secondary)
        } footer: {
            Spacer()
            SaveButton(label: "Save Compressed") { save() }
        }
        .frame(width: 480, height: 320)
        .onAppear { estimateSize() }
        .onChange(of: quality) { _ in estimateSize() }
        .onChange(of: maxPixel) { _ in estimateSize() }
    }

    private func fmt(_ b: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file) }

    private func estimateSize() {
        let q = quality, m = maxPixel, img = original
        estimating = true
        DispatchQueue.global().async {
            var bytes: Int? = nil
            if let resized = try? Img.resized(img, maxPixel: m == 0 ? 100000 : CGFloat(m)) {
                let data = NSMutableData()
                if let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) {
                    let flat = (Img.hasAlpha(resized) ? (try? Img.flatten(resized)) : resized) ?? resized
                    CGImageDestinationAddImage(dest, flat, [kCGImageDestinationLossyCompressionQuality: q] as CFDictionary)
                    if CGImageDestinationFinalize(dest) { bytes = data.length }
                }
            }
            DispatchQueue.main.async {
                if q == quality && m == maxPixel { estimate = bytes; estimating = false }
            }
        }
    }

    private func save() {
        let q = quality, m = maxPixel, targets = urls
        window?.window?.close()
        Runner.run(WheelItem("Compress", "Compressing", symbol: nil) { _ in
            try Img.compress(targets, quality: q, maxPixel: m == 0 ? 100000 : CGFloat(m))
        }, urls: targets)
    }
}

enum Editors {
    static func open(_ which: String, urls: [URL]) throws -> Outcome {
        let img = try Img.load(urls[0])
        switch which {
        case "bg": EditorHost.present(title: "Add Background", size: NSSize(width: 560, height: 640), AddBGView(urls: urls, image: img))
        case "crop": EditorHost.present(title: "Crop", size: NSSize(width: 520, height: 540), CropView(urls: urls, image: img))
        case "compress": EditorHost.present(title: "Compress", size: NSSize(width: 480, height: 320), CompressView(urls: urls, image: img))
        default: break
        }
        return .none
    }
}
