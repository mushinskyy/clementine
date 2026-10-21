import AppKit
import ApplicationServices

/// Intercepts right-clicks (and control-clicks) on Finder windows and the Desktop and
/// shows the wheel instead of Finder's context menu. Needs the Accessibility permission.
/// Hold Option while right-clicking to get Finder's own menu.
final class RightClickTakeover {
    static let shared = RightClickTakeover()
    static let magic: Int64 = 0x434C454D   // "CLEM": marks events we synthesize ourselves

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retry: Timer?
    private var swallowRightUp = false
    private var swallowLeftUp = false
    private var busy = false

    var isTrusted: Bool { AXIsProcessTrusted() }
    var isActive: Bool { tap != nil }

    func requestPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    func openAccessibilitySettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(u) }
    }

    func start() {
        retry?.invalidate()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.reconcile() }
        RunLoop.main.add(t, forMode: .common)
        retry = t
        reconcile()
    }

    /// Keep the tap in step with the preference and the permission.
    private var relaunchScheduled = false

    func reconcile() {
        let want = Prefs.shared.takeover && isTrusted
        if want && tap == nil {
            install()
            if tap == nil && !relaunchScheduled {
                // The permission was granted while running; a fresh process is needed for the tap.
                relaunchScheduled = true
                let path = Bundle.main.bundlePath
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/bin/sh")
                    p.arguments = ["-c", "sleep 1; /usr/bin/open -n \"\(path)\""]
                    try? p.run()
                    NSApp.terminate(nil)
                }
            }
        }
        if !want && tap != nil { uninstall() }
    }

    private func install() {
        let mask: CGEventMask = (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.rightMouseUp.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask,
                                        callback: { _, type, event, _ in RightClickTakeover.shared.handle(type, event) },
                                        userInfo: nil) else { return }
        tap = t
        source = CFMachPortCreateRunLoopSource(nil, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    private func uninstall() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        source = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return pass
        }
        guard Prefs.shared.takeover else { return pass }
        if event.getIntegerValueField(.eventSourceUserData) == Self.magic { return pass }
        let flags = event.flags
        switch type {
        case .rightMouseUp:
            if swallowRightUp { swallowRightUp = false; return nil }
            return pass
        case .leftMouseUp:
            if swallowLeftUp { swallowLeftUp = false; return nil }
            return pass
        case .leftMouseDown:
            guard flags.contains(.maskControl) else { return pass }
        case .rightMouseDown:
            break
        default:
            return pass
        }
        if flags.contains(.maskAlternate) || busy { return pass }
        let loc = event.location
        // Menu bar and Dock strips are never ours.
        if Self.isSystemChrome(loc) { return pass }
        // Ask the accessibility hit-test which app really owns the point (handles the
        // auto-hiding Dock, menu bar extras, popovers); fall back to the window list.
        if let bid = AXProbe.bundleID(at: loc) {
            guard bid == "com.apple.finder" else { return pass }
        }
        guard let hit = Self.window(at: loc), hit.owner == "Finder" else { return pass }
        if type == .rightMouseDown { swallowRightUp = true } else { swallowLeftUp = true }
        busy = true
        let isDesktop = hit.layer < 0
        DispatchQueue.main.async { self.present(at: loc, isDesktop: isDesktop) }
        return nil
    }

    /// True when the point (CG coordinates) lies in the menu bar or the Dock's strip.
    static func isSystemChrome(_ p: CGPoint) -> Bool {
        guard let primary = NSScreen.screens.first else { return false }
        let cocoa = NSPoint(x: p.x, y: primary.frame.maxY - p.y)
        guard let s = NSScreen.screens.first(where: { NSMouseInRect(cocoa, $0.frame, false) }) else { return true }
        return !NSMouseInRect(cocoa, s.visibleFrame, false)
    }

    /// The window that would receive a click at a point (CG coordinates), as (owner name, layer).
    /// Full-screen overlay windows (the Dock's, Notification Center's, wallpaper agents') are skipped,
    /// so a click on empty desktop resolves to Finder's desktop-icons window.
    static func window(at p: CGPoint) -> (owner: String, layer: Int)? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let screenArea = NSScreen.screens.map { $0.frame.width * $0.frame.height }.max() ?? 0
        let desktopIconsLayer = Int(CGWindowLevelForKey(.desktopIconWindow))
        for w in list {
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let wd = b["Width"], let ht = b["Height"] else { continue }
            let alpha = (w[kCGWindowAlpha as String] as? Double) ?? 1
            if alpha <= 0.01 { continue }
            guard CGRect(x: x, y: y, width: wd, height: ht).contains(p) else { continue }
            let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
            let layer = (w[kCGWindowLayer as String] as? Int) ?? 0
            if owner == "Clementine" { return (owner, layer) }
            if layer == desktopIconsLayer { return (owner, layer) }          // Finder's desktop
            if layer < 0 { continue }                                        // wallpaper and below
            if layer != 0 && wd * ht >= screenArea * 0.9 { continue }        // full-screen overlays
            return (owner, layer)                                            // normal window, menu, Dock bar…
        }
        return nil
    }

    private func synthesizeLeftClick(at p: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        src?.userData = Self.magic
        guard let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left),
              let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left) else { return }
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func present(at loc: CGPoint, isDesktop: Bool) {
        let screenPoint = NSEvent.mouseLocation
        let before = FinderActions.selection()
        let hovered = AXProbe.fileURL(at: loc)
        let hoveredSelected = hovered.map { h in before.contains { $0.standardizedFileURL.path == h.standardizedFileURL.path } } ?? false
        if hoveredSelected {
            finish(urls: before, isDesktop: isDesktop, at: screenPoint)
        } else {
            // Let Finder select (or deselect) what's under the pointer, exactly as a right-click would.
            synthesizeLeftClick(at: loc)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.finish(urls: FinderActions.selection(), isDesktop: isDesktop, at: screenPoint)
            }
        }
    }

    private func finish(urls: [URL], isDesktop: Bool, at point: NSPoint) {
        busy = false
        let folder = isDesktop ? FinderActions.desktop : FinderActions.frontFolder()
        let kind: WheelKind = urls.isEmpty ? .finder : (Prefs.shared.firstWheel == "convert" ? .convert : .finder)
        WheelController.shared.showClickable(kind, urls: urls, folder: folder, at: point)
    }
}

/// Finds the file under a screen point through Finder's accessibility tree.
enum AXProbe {
    /// Bundle identifier of the app owning the accessibility element under a point.
    static func bundleID(at p: CGPoint) -> String? {
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &el) == .success, let e = el else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(e, &pid) == .success, pid > 0 else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    static func fileURL(at p: CGPoint) -> URL? {
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &el) == .success, var e = el else { return nil }
        for _ in 0..<6 {
            var v: CFTypeRef?
            if AXUIElementCopyAttributeValue(e, "AXURL" as CFString, &v) == .success, let u = v as? NSURL, u.isFileURL {
                return u as URL
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(e, kAXParentAttribute as CFString, &parent) == .success, let pe = parent else { break }
            e = pe as! AXUIElement
        }
        return nil
    }
}
