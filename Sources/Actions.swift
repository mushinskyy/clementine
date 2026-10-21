import AppKit

enum Actions {
    static func airdrop(_ urls: [URL]) throws -> Outcome {
        guard let service = NSSharingService(named: .sendViaAirDrop) else { throw ConvError("AirDrop isn't available") }
        guard service.canPerform(withItems: urls) else { throw ConvError("AirDrop can't share these items") }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
        return .none
    }

    static func copy(_ urls: [URL]) throws -> Outcome {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
        return .message(urls.count == 1 ? "Copied \(urls[0].lastPathComponent)" : "Copied \(urls.count) items")
    }

    static func copyPath(_ urls: [URL]) throws -> Outcome {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
        return .message(urls.count == 1 ? "Copied path" : "Copied \(urls.count) paths")
    }

    static func move(_ urls: [URL]) throws -> Outcome {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Move Here"
        panel.message = urls.count == 1 ? "Move \(urls[0].lastPathComponent) to…" : "Move \(urls.count) items to…"
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { resp in
            guard resp == .OK, let dir = panel.url else { return }
            var moved = 0
            for u in urls {
                let dest = Output.unique(dir.appendingPathComponent(u.lastPathComponent))
                do { try FileManager.default.moveItem(at: u, to: dest); moved += 1 }
                catch { Toast.show(error.localizedDescription, style: .error); return }
            }
            Toast.show("Moved \(moved) \(moved == 1 ? "item" : "items") to \(dir.lastPathComponent)", style: .success, reveal: dir)
        }
        return .none
    }

    static func terminal(_ urls: [URL]) throws -> Outcome {
        let u = urls[0]
        let dir = Kinds.kind(of: u) == .folder ? u : u.deletingLastPathComponent()
        let ws = NSWorkspace.shared
        let app = ws.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2") ?? ws.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
        guard let app else { throw ConvError("No terminal app found") }
        ws.open([dir], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        return .none
    }

    static func float(_ urls: [URL]) throws -> Outcome {
        Shelf.shared.add(urls)
        return .none
    }

    static func duplicate(_ urls: [URL]) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            let dest = Output.unique(u.deletingLastPathComponent().appendingPathComponent(u.deletingPathExtension().lastPathComponent + " copy").appendingPathExtension(u.pathExtension))
            try FileManager.default.copyItem(at: u, to: dest)
            outs.append(dest)
        }
        return .files(outs)
    }
}

// MARK: - Floating shelf

final class Shelf: NSObject {
    static let shared = Shelf()
    private let panel: NSPanel
    private let stack = NSStackView()
    private let scroll = NSScrollView()
    private let empty = NSTextField(labelWithString: "Drop files here")
    private var items: [URL] = []

    private override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 320),
                        styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        super.init()
        panel.title = "Shelf"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 200, height: 160)

        let root = ShelfDropView()
        root.onDrop = { [weak self] urls in self?.add(urls) }
        panel.contentView = root

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let clip = FlippedClipView()
        scroll.contentView = clip
        scroll.documentView = stack
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)

        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.translatesAutoresizingMaskIntoConstraints = false
        let clear = NSButton(title: "Clear", target: self, action: #selector(clearAll))
        clear.bezelStyle = .inline
        clear.controlSize = .small
        let hint = NSTextField(labelWithString: "Drag items out into any app")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        bar.addArrangedSubview(hint)
        bar.addArrangedSubview(NSView())
        bar.addArrangedSubview(clear)
        root.addSubview(bar)

        empty.textColor = .tertiaryLabelColor
        empty.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(empty)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bar.topAnchor),
            stack.widthAnchor.constraint(equalTo: clip.widthAnchor),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            bar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -6),
            bar.heightAnchor.constraint(equalToConstant: 24),
            empty.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
    }

    func show() {
        if !panel.isVisible, let f = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: f.maxX - panel.frame.width - 16, y: f.midY - panel.frame.height / 2))
        }
        panel.orderFrontRegardless()
    }

    func add(_ urls: [URL]) {
        for u in urls where !items.contains(u) {
            items.append(u)
            let v = ShelfItemView(url: u)
            v.onRemove = { [weak self, weak v] in
                guard let self, let v else { return }
                self.items.removeAll { $0 == u }
                self.stack.removeArrangedSubview(v); v.removeFromSuperview()
                self.empty.isHidden = !self.items.isEmpty
            }
            stack.addArrangedSubview(v)
            v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16).isActive = true
        }
        empty.isHidden = !items.isEmpty
        show()
    }

    @objc private func clearAll() {
        items.removeAll()
        for v in stack.arrangedSubviews { stack.removeArrangedSubview(v); v.removeFromSuperview() }
        empty.isHidden = false
    }
}

final class FlippedClipView: NSClipView { override var isFlipped: Bool { true } }

final class ShelfDropView: NSView {
    var onDrop: (([URL]) -> Void)?
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .link }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL] else { return false }
        onDrop?(urls)
        return true
    }
}

final class ShelfItemView: NSView, NSDraggingSource {
    let url: URL
    var onRemove: (() -> Void)?
    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")

    init(url: URL) {
        self.url = url
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        icon.image = NSWorkspace.shared.icon(forFile: url.path)
        icon.translatesAutoresizingMaskIntoConstraints = false
        name.stringValue = url.lastPathComponent
        name.lineBreakMode = .byTruncatingMiddle
        name.font = .systemFont(ofSize: 12)
        name.translatesAutoresizingMaskIntoConstraints = false
        let remove = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove")!, target: self, action: #selector(removeTapped))
        remove.isBordered = false
        remove.translatesAutoresizingMaskIntoConstraints = false
        remove.contentTintColor = .tertiaryLabelColor
        addSubview(icon); addSubview(name); addSubview(remove)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 28), icon.heightAnchor.constraint(equalToConstant: 28),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            name.trailingAnchor.constraint(equalTo: remove.leadingAnchor, constant: -6),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            remove.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            remove.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func removeTapped() { onRemove?() }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { NSWorkspace.shared.open(url); return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 48, height: 48)
        item.setDraggingFrame(NSRect(x: event.locationInWindow.x - 24, y: 0, width: 48, height: 48), contents: img)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .link, .generic] : []
    }
    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) { WheelController.shared.isOwnDrag = true }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { WheelController.shared.isOwnDrag = false }
}
