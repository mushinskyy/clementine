import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = StatusIcon.make()
        statusItem.button?.toolTip = "Clementine — drag a file and tap a key"

        let menu = NSMenu()
        menu.addItem(withTitle: "Right-click in Finder for the wheel", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Convert Files…", action: #selector(pickFiles), keyEquivalent: "o")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Show Shelf", action: #selector(showShelf), keyEquivalent: "")
        menu.addItem(withTitle: "Welcome & Tips", action: #selector(showWelcome), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "About Clementine", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(withTitle: "Quit Clementine", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        statusItem.menu = menu

        NSApp.servicesProvider = ServiceProvider()
        NSUpdateDynamicServices()
        // No context menus anywhere in Clementine's own windows: right-clicks and
        // control-clicks are swallowed; on the wheel they count as a normal click.
        NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .rightMouseUp, .leftMouseDown]) { e in
            if e.type == .leftMouseDown && !e.modifierFlags.contains(.control) { return e }
            guard let w = e.window else { return e }
            if w === WheelController.shared.panel, e.type != .rightMouseUp {
                WheelController.shared.view.mouseDown(with: e)
            }
            return nil
        }
        FF.warmUp()
        DragMonitor.shared.start()
        RightClickTakeover.shared.start()
        if !Prefs.shared.welcomed { showWelcome() }
        else if Prefs.shared.takeover && !RightClickTakeover.shared.isTrusted { RightClickTakeover.shared.requestPermission() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls where u.scheme == "clementine" { ShellBridge.handle(u) }
    }

    @objc func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Choose"
        panel.message = "Choose files to convert or process"
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { resp in
            guard resp == .OK, !panel.urls.isEmpty else { return }
            let f = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            WheelController.shared.showClickable(.convert, urls: panel.urls, at: NSPoint(x: f.midX, y: f.midY))
        }
    }

    @objc func showShelf() { Shelf.shared.show() }

    @objc func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 400), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Clementine Settings"
            w.contentView = NSHostingView(rootView: SettingsView())
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showWelcome() {
        if welcomeWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 520), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: WelcomeView { [weak self] in
                Prefs.shared.welcomed = true
                self?.welcomeWindow?.close()
            })
            w.center()
            welcomeWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Right-click a file in Finder and pick what to do with it.\nEverything runs on your Mac."),
            .applicationName: "Clementine",
        ])
    }
}

enum StatusIcon {
    static func make() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let r = rect.insetBy(dx: 2, dy: 2)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: r).fill()
            // segment lines, like a sliced citrus
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
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - 1.6, y: c.y - 1.6, width: 3.2, height: 3.2)).fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}

// Command-line entry used by the Finder Quick Actions:
//   Clementine --pick <files…>              → opens the option picker
//   Clementine --run <wheel> <item> <files…> → runs one option directly
// This runs before NSApplication exists so Launch Services doesn't mistake this
// process for the app itself; the URL is handed to /usr/bin/open, which launches the app.
if CommandLine.arguments.count >= 3, ["--pick", "--run"].contains(CommandLine.arguments[1]) {
    let a = CommandLine.arguments
    var c = URLComponents()
    c.scheme = "clementine"
    var q: [URLQueryItem] = []
    var files: [String]
    if a[1] == "--pick" { c.host = "pick"; files = Array(a[2...]) }
    else {
        guard a.count >= 5 else { exit(2) }
        c.host = "run"; q = [URLQueryItem(name: "wheel", value: a[2]), URLQueryItem(name: "item", value: a[3])]; files = Array(a[4...])
    }
    q += files.map { URLQueryItem(name: "path", value: URL(fileURLWithPath: $0).path) }
    c.queryItems = q
    guard let url = c.url else { exit(2) }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    p.arguments = [url.absoluteString]
    try? p.run()
    p.waitUntilExit()
    exit(Int32(p.terminationStatus))
}
let app = NSApplication.shared
// Documentation aid: `Clementine --screenshots <sample image> <output dir>` captures the
// four wheels, the Add Background editor and Settings into PNG files.
if CommandLine.arguments.count >= 4, CommandLine.arguments[1] == "--screenshots" {
    let sample = URL(fileURLWithPath: CommandLine.arguments[2])
    let dir = URL(fileURLWithPath: CommandLine.arguments[3])
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    NSApp.appearance = NSAppearance(named: .aqua)
    FF.warmUp(sync: true)
    WheelView.fakeGlass = true
    let wc = WheelController.shared
    wc.panel.appearance = NSAppearance(named: .aqua)
    wc.view.removeFromSuperview()
    wc.view.frame = NSRect(origin: .zero, size: WheelView.panelSize)
    wc.panel.contentView = wc.view
    wc.renderPreviews(for: sample, into: dir)
    func capture(_ w: NSWindow, _ name: String) {
        w.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.windowNumber), [.bestResolution]) {
            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
        }
        w.close()
    }
    if let img = try? Img.load(sample) {
        EditorHost.present(title: "Add Background", size: NSSize(width: 560, height: 640), AddBGView(urls: [sample], image: img))
        if let w = NSApp.windows.last(where: { $0.title == "Add Background" }) { capture(w, "editor-add-background.png") }
        EditorHost.present(title: "Compress", size: NSSize(width: 480, height: 320), CompressView(urls: [sample], image: img))
        if let w = NSApp.windows.last(where: { $0.title == "Compress" }) { capture(w, "editor-compress.png") }
    }
    let sw = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 640), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    sw.title = "Clementine Settings"
    sw.contentView = NSHostingView(rootView: SettingsView())
    sw.center()
    capture(sw, "settings.png")
    let ww = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 560), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
    ww.titlebarAppearsTransparent = true; ww.titleVisibility = .hidden
    ww.contentView = NSHostingView(rootView: WelcomeView(onDone: {}))
    ww.center()
    capture(ww, "welcome.png")
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
