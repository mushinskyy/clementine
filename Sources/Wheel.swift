import AppKit

enum Outcome {
    case files([URL])
    case message(String)
    case none
}

struct WheelItem {
    let title: String          // short label on the segment, e.g. "PNG"
    let caption: String        // sentence under the wheel, e.g. "Convert to PNG"
    let symbol: String?        // SF Symbol name for tools / actions
    let onMain: Bool           // run on the main thread (UI actions)
    let run: ([URL]) throws -> Outcome

    init(_ title: String, _ caption: String, symbol: String? = nil, onMain: Bool = false, run: @escaping ([URL]) throws -> Outcome) {
        self.title = title; self.caption = caption; self.symbol = symbol; self.onMain = onMain; self.run = run
    }
}

final class WheelPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class WheelController {
    static let shared = WheelController()

    let panel: WheelPanel
    let view: WheelView
    private(set) var kind: WheelKind?
    private(set) var items: [WheelItem] = []
    private(set) var urls: [URL] = []
    private(set) var folder: URL?
    private(set) var page = 0
    private(set) var clickMode = false
    private(set) var hubIcon: NSImage?
    var isOwnDrag = false

    static let perPage = 8

    private init() {
        view = WheelView(frame: NSRect(x: 0, y: 0, width: WheelView.panelSize.width, height: WheelView.panelSize.height))
        panel = WheelPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        let glass = NSVisualEffectView(frame: view.frame)
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.autoresizingMask = [.width, .height]
        view.autoresizingMask = [.width, .height]
        glass.addSubview(view)
        panel.contentView = glass
        view.glass = glass
        view.controller = self
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            guard let self, self.clickMode else { return }
            self.hide()
        }
    }

    var pageCount: Int {
        if items.count <= WheelController.perPage { return 1 }
        return Int(ceil(Double(items.count) / Double(WheelController.perPage - 1)))
    }

    /// Items visible on the current page, plus a trailing "More" placeholder when paged.
    var visibleItems: [WheelItem?] {
        if items.count <= WheelController.perPage { return items.map { $0 } }
        let per = WheelController.perPage - 1
        let start = page * per
        let slice = Array(items[start..<min(items.count, start + per)])
        return slice.map { $0 } + [nil]
    }

    /// Wheels the tab strip offers in click mode.
    var availableKinds: [WheelKind] {
        urls.isEmpty ? [.finder] : WheelKind.allCases
    }

    // MARK: drag mode (wheel appears while dragging; drop on a segment)

    func show(_ kind: WheelKind, urls: [URL], at point: NSPoint) {
        if panel.isVisible, self.kind == kind, !clickMode {
            nextPage()
            return
        }
        clickMode = false
        folder = nil
        load(kind, urls: urls)
        position(at: point)
        panel.orderFrontRegardless()
    }

    // MARK: click mode (wheel appears on right-click or from Finder; click a segment)

    func showClickable(_ kind: WheelKind, urls: [URL], folder: URL? = nil, at point: NSPoint) {
        if panel.isVisible { panel.orderOut(nil) }
        clickMode = true
        self.folder = folder
        load(kind, urls: urls)
        position(at: point)
        popIn()
        panel.makeKey()
        panel.makeFirstResponder(view)
    }

    private func popIn() {
        guard let layer = panel.contentView?.layer else { panel.orderFrontRegardless(); return }
        let size = panel.frame.size
        layer.anchorPoint = CGPoint(x: 0.5, y: WheelView.wheelCenterY / size.height)
        layer.position = CGPoint(x: size.width / 2, y: WheelView.wheelCenterY)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.82; scale.toValue = 1
        scale.duration = 0.22
        scale.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.1, 0.3, 1)
        layer.add(scale, forKey: "pop")
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            self.panel.animator().alphaValue = 1
        }
    }

    func switchWheel(_ kind: WheelKind) {
        guard clickMode, availableKinds.contains(kind) else { return }
        load(kind, urls: urls)
    }

    func load(_ kind: WheelKind, urls: [URL]) {
        self.kind = kind
        self.urls = urls
        self.items = ItemBuilder.items(for: kind, urls: urls, folder: folder)
        self.page = 0
        if let f = urls.first { hubIcon = NSWorkspace.shared.icon(forFile: f.path) }
        else if let d = folder { hubIcon = NSWorkspace.shared.icon(forFile: d.path) }
        else { hubIcon = nil }
        view.hovered = nil
        view.reload()
    }

    private func position(at point: NSPoint) {
        var origin = NSPoint(x: point.x - WheelView.panelSize.width / 2, y: point.y - WheelView.wheelCenterY)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main {
            let f = screen.visibleFrame
            origin.x = min(max(origin.x, f.minX), f.maxX - WheelView.panelSize.width)
            origin.y = min(max(origin.y, f.minY), f.maxY - WheelView.panelSize.height)
        }
        panel.setFrameOrigin(origin)
    }

    /// Debug aid: shows each wheel on screen and captures its window into PNGs (used by `--render-wheel`).
    func renderPreviews(for url: URL, into dir: URL) {
        let f = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        for kind in WheelKind.allCases {
            showClickable(kind, urls: [url], at: NSPoint(x: f.midX, y: f.midY))
            view.hovered = 0
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            let id = CGWindowID(panel.windowNumber)
            if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .bestResolution]) {
                let rep = NSBitmapImageRep(cgImage: cg)
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("wheel-\(kind.rawValue).png"))
            }
        }
        hide()
    }

    func nextPage() {
        guard pageCount > 1 else { return }
        page = (page + 1) % pageCount
        view.hovered = nil
        view.reload()
    }

    func dragEnded() {
        guard !clickMode else { return }
        // Give a pending drop a moment to arrive before tearing the wheel down.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, !self.view.dropInProgress, !self.clickMode else { return }
            self.hide()
        }
    }

    func hide() {
        panel.orderOut(nil)
        kind = nil
        clickMode = false
        view.hovered = nil
    }

    func perform(_ item: WheelItem, urls: [URL]) {
        hide()
        Runner.run(item, urls: urls)
    }
}

enum Runner {
    static func run(_ item: WheelItem, urls: [URL]) {
        let verb = item.caption
        if item.onMain {
            do {
                let outcome = try item.run(urls)
                report(outcome, verb: verb)
            } catch {
                Toast.show(error.localizedDescription, style: .error)
            }
            return
        }
        Toast.show("\(verb)…", style: .working, sticky: true)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let outcome = try item.run(urls)
                DispatchQueue.main.async { report(outcome, verb: verb) }
            } catch {
                DispatchQueue.main.async { Toast.show(error.localizedDescription, style: .error) }
            }
        }
    }

    private static func report(_ outcome: Outcome, verb: String) {
        switch outcome {
        case .files(let files):
            guard let first = files.first else { Toast.show("Done", style: .success); return }
            let text = files.count == 1 ? "Saved \(first.lastPathComponent)" : "Saved \(files.count) files"
            Toast.show(text, style: .success, reveal: first)
            if Prefs.shared.playSound { NSSound(named: "Pop")?.play() }
        case .message(let m):
            Toast.show(m, style: .success)
        case .none:
            Toast.hide()
        }
    }
}

// MARK: - Wheel view

final class WheelView: NSView {
    static let panelSize = NSSize(width: 260, height: 300)
    static let wheelCenterY: CGFloat = 160       // from the bottom of the panel
    static let outerRadius: CGFloat = 96
    static let innerRadius: CGFloat = 36
    static let tabRowY: CGFloat = 279            // center line of the tab strip

    weak var controller: WheelController?
    weak var glass: NSVisualEffectView?
    var hovered: Int? { didSet { if hovered != oldValue { needsDisplay = true; updateMask() } } }
    var hoveredTab: WheelKind? { didSet { if hoveredTab != oldValue { needsDisplay = true } } }
    var dropInProgress = false
    private var moreHoverStart: Date?
    private var prevFlags: NSEvent.ModifierFlags = []
    private var tracking: NSTrackingArea?

    private var orange: NSColor { NSColor.controlAccentColor }
    private var orangeDeep: NSColor { NSColor.controlAccentColor.blended(withFraction: 0.22, of: .black) ?? NSColor.controlAccentColor }
    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
    private var segment: NSColor { isDark ? NSColor.white.withAlphaComponent(0.10) : NSColor.white.withAlphaComponent(0.55) }
    private var segmentHot: NSColor { isDark ? NSColor.white.withAlphaComponent(0.18) : NSColor.white.withAlphaComponent(0.8) }
    private var ink: NSColor { .labelColor }
    private var edge: NSColor { isDark ? NSColor.white.withAlphaComponent(0.14) : NSColor.white.withAlphaComponent(0.9) }
    private var tint: NSColor { NSColor.controlAccentColor }

    private func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let d = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { return f }
        return base
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var center: NSPoint { NSPoint(x: bounds.midX, y: WheelView.wheelCenterY) }

    func reload() {
        moreHoverStart = nil
        needsDisplay = true
        updateMask()
    }

    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }

    /// Screenshot mode: paint an opaque-ish glass stand-in since a window capture has no backdrop.
    static var fakeGlass = false

    private func glassShape() -> NSBezierPath {
        let shape = NSBezierPath()
        let ro = WheelView.outerRadius
        shape.appendOval(in: NSRect(x: center.x - ro, y: center.y - ro, width: ro * 2, height: ro * 2))
        for t in tabs { shape.append(NSBezierPath(roundedRect: t.rect, xRadius: t.rect.height / 2, yRadius: t.rect.height / 2)) }
        let pill = captionPill()
        shape.append(NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2))
        return shape
    }

    /// Shape of the frosted glass: the donut, the tab pills and the caption pill.
    private func updateMask() {
        guard let g = glass else { return }
        let shape = glassShape()
        let img = NSImage(size: bounds.size, flipped: false) { _ in
            NSColor.black.setFill(); shape.fill(); return true
        }
        img.resizingMode = .stretch
        g.maskImage = img
    }

    private func captionText() -> String {
        guard let c = controller else { return "" }
        let items = c.visibleItems
        if let h = hovered { return items[h]?.caption ?? (c.clickMode ? "Click for more options" : "Keep hovering for more options") }
        if c.clickMode {
            let name = c.urls.count == 1 ? c.urls[0].lastPathComponent : (c.urls.isEmpty ? (c.folder?.lastPathComponent ?? "") : "\(c.urls.count) items")
            return c.pageCount > 1 ? "\(name)  ·  page \(c.page + 1) of \(c.pageCount)" : name
        }
        if c.pageCount > 1 { return "\(c.kind?.title ?? "")  ·  page \(c.page + 1) of \(c.pageCount)" }
        return c.kind?.title ?? ""
    }

    private var captionAttrs: [NSAttributedString.Key: Any] { [.font: rounded(11, .semibold), .foregroundColor: ink] }

    private func captionPill() -> NSRect {
        let cs = NSAttributedString(string: captionText(), attributes: captionAttrs)
        var csz = cs.size()
        csz.width = min(csz.width, bounds.width - 40)
        return NSRect(x: center.x - csz.width / 2 - 12, y: 14, width: csz.width + 24, height: csz.height + 12)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    // MARK: geometry

    private func segmentIndex(at p: NSPoint) -> Int? {
        guard let c = controller else { return nil }
        let n = c.visibleItems.count
        guard n > 0 else { return nil }
        let dx = p.x - center.x, dy = p.y - center.y
        let r = sqrt(dx * dx + dy * dy)
        guard r >= WheelView.innerRadius, r <= WheelView.outerRadius + 6 else { return nil }
        if n == 1 { return 0 }
        var angle = atan2(dy, dx) * 180 / .pi      // 0 = right, 90 = top, counter-clockwise
        let step = 360.0 / CGFloat(n)
        angle = 90 - angle + step / 2
        while angle < 0 { angle += 360 }
        while angle >= 360 { angle -= 360 }
        return Int(angle / step) % n
    }

    private struct Tab { let kind: WheelKind; let rect: NSRect; let symbol: String }

    private var tabs: [Tab] {
        guard let c = controller, c.clickMode else { return [] }
        let kinds = c.availableKinds
        let w: CGFloat = 58, h: CGFloat = 28, gap: CGFloat = 5
        let total = CGFloat(kinds.count) * w + CGFloat(kinds.count - 1) * gap
        var x = bounds.midX - total / 2
        return kinds.map { k in
            let r = NSRect(x: x, y: WheelView.tabRowY - h / 2, width: w, height: h)
            x += w + gap
            return Tab(kind: k, rect: r, symbol: k.symbol)
        }
    }

    // MARK: drag destination

    private func update(_ sender: NSDraggingInfo) {
        let p = convert(sender.draggingLocation, from: nil)
        let idx = segmentIndex(at: p)
        hovered = idx
        if let idx, let c = controller, c.visibleItems[idx] == nil {
            if moreHoverStart == nil { moreHoverStart = Date() }
            if let s = moreHoverStart, Date().timeIntervalSince(s) > 0.6 {
                moreHoverStart = nil
                c.nextPage()
            }
        } else {
            moreHoverStart = nil
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender); return .generic }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender); return .generic }
    override func draggingExited(_ sender: NSDraggingInfo?) { hovered = nil; moreHoverStart = nil }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropInProgress = true
        defer { dropInProgress = false }
        guard let c = controller else { return false }
        let p = convert(sender.draggingLocation, from: nil)
        guard let idx = segmentIndex(at: p), let item = c.visibleItems[idx] else {
            c.hide()
            return true
        }
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let dropped = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL]) ?? []
        let urls = dropped.isEmpty ? c.urls : dropped
        c.perform(item, urls: urls)
        return true
    }

    // MARK: click mode input

    override func mouseMoved(with event: NSEvent) {
        guard let c = controller, c.clickMode else { return }
        let p = convert(event.locationInWindow, from: nil)
        hovered = segmentIndex(at: p)
        hoveredTab = tabs.first { $0.rect.contains(p) }?.kind
    }

    override func mouseExited(with event: NSEvent) {
        guard let c = controller, c.clickMode else { return }
        hovered = nil
        hoveredTab = nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let c = controller, c.clickMode else { return }
        let p = convert(event.locationInWindow, from: nil)
        if let tab = tabs.first(where: { $0.rect.contains(p) }) {
            c.switchWheel(tab.kind)
            return
        }
        if let idx = segmentIndex(at: p) {
            if let item = c.visibleItems[idx] { c.perform(item, urls: c.urls) } else { c.nextPage() }
            return
        }
        let dx = p.x - center.x, dy = p.y - center.y
        if sqrt(dx * dx + dy * dy) > WheelView.outerRadius + 6 && !captionRect.contains(p) { c.hide() }
    }

    override func rightMouseDown(with event: NSEvent) { mouseDown(with: event) }

    override func keyDown(with event: NSEvent) {
        guard let c = controller, c.clickMode else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 53: c.hide()                                   // esc
        case 49, 36: if let h = hovered, let item = c.visibleItems[h] { c.perform(item, urls: c.urls) }   // space / return
        case 48: // tab cycles wheels
            let kinds = c.availableKinds
            if let k = c.kind, let i = kinds.firstIndex(of: k) { c.switchWheel(kinds[(i + 1) % kinds.count]) }
        default:
            if let n = Int(event.charactersIgnoringModifiers ?? ""), n >= 1, n <= c.visibleItems.count, let item = c.visibleItems[n - 1] {
                c.perform(item, urls: c.urls)
            } else { super.keyDown(with: event) }
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard let c = controller, c.clickMode else { super.flagsChanged(with: event); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let newly = flags.subtracting(prevFlags)
        prevFlags = flags
        for kind in [WheelKind.convert, .tools, .actions] {
            if let f = Prefs.shared.key(for: kind).flag, newly.contains(f) {
                if kind == c.kind { c.nextPage() } else { c.switchWheel(kind) }
                return
            }
        }
        if newly.contains(.option) { c.switchWheel(.finder) }
    }

    override func cancelOperation(_ sender: Any?) { controller?.hide() }

    private var captionRect: NSRect = .zero

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let c = controller else { return }
        let items = c.visibleItems
        let n = items.count
        let ctx = NSGraphicsContext.current!
        if WheelView.fakeGlass {
            ctx.saveGraphicsState()
            let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.18); sh.shadowBlurRadius = 24; sh.shadowOffset = NSSize(width: 0, height: -10); sh.set()
            (isDark ? NSColor(white: 0.16, alpha: 0.96) : NSColor(white: 1, alpha: 0.82)).setFill()
            glassShape().fill()
            ctx.restoreGraphicsState()
        }
        let soft = NSShadow()
        soft.shadowColor = NSColor.black.withAlphaComponent(isDark ? 0.5 : 0.18)
        soft.shadowBlurRadius = 22
        soft.shadowOffset = NSSize(width: 0, height: -8)

        // Glass edge of the donut
        let ro = WheelView.outerRadius, ri = WheelView.innerRadius
        let donut = NSBezierPath(ovalIn: NSRect(x: center.x - ro + 0.5, y: center.y - ro + 0.5, width: ro * 2 - 1, height: ro * 2 - 1))
        edge.setStroke(); donut.lineWidth = 1; donut.stroke()

        // Segments: translucent white cards separated by thin gaps that show the glass through
        let step = 360.0 / CGFloat(max(n, 1))
        let gapDeg: CGFloat = n > 1 ? 1.6 : 0
        for i in 0..<n {
            let centerAngle = 90 - CGFloat(i) * step
            let a0 = centerAngle - step / 2 + gapDeg
            let a1 = centerAngle + step / 2 - gapDeg
            let path = NSBezierPath()
            let so = ro - 6, si = ri + 5
            if n == 1 {
                path.appendOval(in: NSRect(x: center.x - so, y: center.y - so, width: so * 2, height: so * 2))
                path.append(NSBezierPath(ovalIn: NSRect(x: center.x - si, y: center.y - si, width: si * 2, height: si * 2)).reversed)
            } else {
                path.appendArc(withCenter: center, radius: so, startAngle: a0, endAngle: a1, clockwise: false)
                path.appendArc(withCenter: center, radius: si, startAngle: a1, endAngle: a0, clockwise: true)
                path.close()
            }
            let isHot = hovered == i
            if isHot {
                ctx.saveGraphicsState()
                path.addClip()
                let g = NSGradient(starting: orange, ending: orangeDeep)!
                g.draw(in: path.bounds, angle: -70)
                ctx.restoreGraphicsState()
            } else {
                segment.setFill(); path.fill()
            }

            let mid = (ro + ri) / 2 + 3
            let rad = centerAngle * .pi / 180
            let lp = NSPoint(x: center.x + cos(rad) * mid, y: center.y + sin(rad) * mid)
            let item = items[i]
            let title = item?.title ?? "More"
            let symbol = item?.symbol ?? "ellipsis.circle.fill"
            let color = isHot ? NSColor.white : ink
            let hasSymbol = item?.symbol != nil || item == nil
            let s = NSAttributedString(string: title, attributes: [.font: rounded(hasSymbol ? 9 : 12.5, hasSymbol ? .semibold : .bold), .foregroundColor: color])
            let size = s.size()
            if hasSymbol, let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .medium)) {
                let tinted = img.tinted(color)
                let isz = tinted.size
                tinted.draw(in: NSRect(x: lp.x - isz.width / 2, y: lp.y - 1, width: isz.width, height: isz.height))
                s.draw(at: NSPoint(x: lp.x - size.width / 2, y: lp.y - 2 - size.height))
            } else {
                s.draw(at: NSPoint(x: lp.x - size.width / 2, y: lp.y - size.height / 2))
            }
        }

        // Hub: clear glass with a fine edge, showing the file icon
        let hubR = ri - 1
        let hub = NSBezierPath(ovalIn: NSRect(x: center.x - hubR, y: center.y - hubR, width: hubR * 2, height: hubR * 2))
        (isDark ? NSColor.white.withAlphaComponent(0.06) : NSColor.white.withAlphaComponent(0.35)).setFill(); hub.fill()
        edge.setStroke(); hub.lineWidth = 1; hub.stroke()
        if let h = hovered {
            let text = items[h]?.title ?? "More"
            let hs = NSAttributedString(string: text, attributes: [.font: rounded(10, .bold), .foregroundColor: ink])
            var hsz = hs.size()
            hsz.width = min(hsz.width, hubR * 2 - 10)
            hs.draw(in: NSRect(x: center.x - hsz.width / 2, y: center.y - hsz.height / 2, width: hsz.width, height: hsz.height))
        } else if let icon = c.hubIcon {
            let isz: CGFloat = 34
            ctx.saveGraphicsState(); soft.set()
            icon.draw(in: NSRect(x: center.x - isz / 2, y: center.y - isz / 2, width: isz, height: isz))
            ctx.restoreGraphicsState()
            if c.urls.count > 1 {
                let badge = NSRect(x: center.x + 6, y: center.y + 8, width: 20, height: 16)
                NSColor.systemRed.setFill()
                NSBezierPath(roundedRect: badge, xRadius: 9.5, yRadius: 9.5).fill()
                let bs = NSAttributedString(string: "\(c.urls.count)", attributes: [.font: rounded(11, .bold), .foregroundColor: NSColor.white])
                let bsz = bs.size()
                bs.draw(at: NSPoint(x: badge.midX - bsz.width / 2, y: badge.midY - bsz.height / 2))
            }
        } else {
            let hs = NSAttributedString(string: c.urls.count == 1 ? "1 file" : "\(c.urls.count) files", attributes: [.font: rounded(11, .semibold), .foregroundColor: ink])
            let hsz = hs.size()
            hs.draw(at: NSPoint(x: center.x - hsz.width / 2, y: center.y - hsz.height / 2))
        }

        // Tab strip: iOS segmented-control pills
        for tab in tabs {
            let current = tab.kind == c.kind
            let hot = tab.kind == hoveredTab
            let pill = NSBezierPath(roundedRect: tab.rect, xRadius: tab.rect.height / 2, yRadius: tab.rect.height / 2)
            if current {
                ctx.saveGraphicsState(); pill.addClip()
                NSGradient(starting: orange, ending: orangeDeep)!.draw(in: tab.rect, angle: -70)
                ctx.restoreGraphicsState()
            } else {
                (hot ? segmentHot : segment).setFill(); pill.fill()
            }
            edge.setStroke(); pill.lineWidth = 1; pill.stroke()
            let color = current ? NSColor.white : ink
            let label = NSAttributedString(string: tab.kind.title, attributes: [.font: rounded(10, .semibold), .foregroundColor: color])
            let lsz = label.size()
            if let img = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 10.5, weight: .semibold)) {
                let t = img.tinted(color)
                let total = t.size.width + 5 + lsz.width
                let x0 = tab.rect.midX - total / 2
                t.draw(in: NSRect(x: x0, y: tab.rect.midY - t.size.height / 2, width: t.size.width, height: t.size.height))
                label.draw(at: NSPoint(x: x0 + t.size.width + 5, y: tab.rect.midY - lsz.height / 2))
            } else {
                label.draw(at: NSPoint(x: tab.rect.midX - lsz.width / 2, y: tab.rect.midY - lsz.height / 2))
            }
        }

        // Caption pill
        let caption = captionText()
        let pill = captionPill()
        captionRect = pill
        let pillPath = NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2)
        segment.setFill(); pillPath.fill()
        edge.setStroke(); pillPath.lineWidth = 1; pillPath.stroke()
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingMiddle; para.alignment = .center
        let cs = NSAttributedString(string: caption, attributes: captionAttrs.merging([.paragraphStyle: para]) { $1 })
        let csz = cs.size()
        cs.draw(in: NSRect(x: pill.minX + 12, y: pill.minY + 6, width: pill.width - 24, height: csz.height))
    }
}

extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let img = NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        return img
    }
}
