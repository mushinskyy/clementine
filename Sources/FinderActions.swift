import AppKit

/// Finder's own context-menu actions, driven through Apple Events and keystrokes.
enum FinderActions {
    private static var cache: [String: NSAppleScript] = [:]

    @discardableResult
    static func script(_ key: String, _ source: String) -> NSAppleEventDescriptor? {
        let s: NSAppleScript
        if let c = cache[key] { s = c } else {
            guard let n = NSAppleScript(source: source) else { return nil }
            var err: NSDictionary?
            n.compileAndReturnError(&err)
            cache[key] = n
            s = n
        }
        var err: NSDictionary?
        let r = s.executeAndReturnError(&err)
        if let err { NSLog("Finder script error: \(err)") }
        return r
    }

    static func quoted(_ p: String) -> String { "\"" + p.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }

    static var desktop: URL { FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0] }

    /// Files currently selected in Finder.
    static func selection() -> [URL] {
        let src = """
        tell application "Finder"
            set out to ""
            try
                repeat with i in (get selection as alias list)
                    set out to out & POSIX path of i & linefeed
                end repeat
            end try
            return out
        end tell
        """
        guard let r = script("selection", src), let s = r.stringValue else { return [] }
        return s.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }

    /// Folder shown in the front Finder window, or the Desktop.
    static func frontFolder() -> URL {
        let src = """
        tell application "Finder"
            try
                if (count of Finder windows) > 0 then return POSIX path of (target of front Finder window as alias)
            end try
            return POSIX path of (path to desktop folder)
        end tell
        """
        guard let r = script("front", src), let s = r.stringValue, !s.isEmpty else { return desktop }
        return URL(fileURLWithPath: s)
    }

    static func activateFinder(then: @escaping () -> Void) {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: then)
    }

    static func postKey(_ code: CGKeyCode, flags: CGEventFlags = []) {
        let src = CGEventSource(stateID: .hidSystemState)
        src?.userData = RightClickTakeover.magic
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { continue }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }
    }

    static func select(_ urls: [URL]) {
        let list = urls.map { "POSIX file \(quoted($0.path)) as alias" }.joined(separator: ", ")
        script("select-\(urls.count)", "tell application \"Finder\" to select {\(list)}")
    }

    // MARK: actions on a selection

    static func open(_ urls: [URL]) throws -> Outcome { urls.forEach { NSWorkspace.shared.open($0) }; return .none }

    static func quickLook(_ urls: [URL]) throws -> Outcome {
        select(urls)
        activateFinder { postKey(49) }                        // space
        return .none
    }

    static func getInfo(_ urls: [URL]) throws -> Outcome {
        let body = urls.map { "open information window of (POSIX file \(quoted($0.path)) as alias)" }.joined(separator: "\n")
        script("info-\(urls.map(\.path).joined())", "tell application \"Finder\"\nactivate\n\(body)\nend tell")
        return .none
    }

    static func rename(_ urls: [URL]) throws -> Outcome {
        guard let u = urls.first else { return .none }
        select([u])
        activateFinder { postKey(36) }                        // return starts renaming
        return .none
    }

    private static let trashSound: NSSound? = NSSound(contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/finder/move to trash.aif", byReference: true)

    /// Finder's own "move to trash" sound, unless interface sounds are off in System Settings.
    static func playTrashSound() {
        let enabled = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.sound.uiaudio.enabled"] as? Int ?? 1
        guard enabled != 0 else { return }
        trashSound?.stop()
        trashSound?.play()
    }

    static func trash(_ urls: [URL]) throws -> Outcome {
        for u in urls { try FileManager.default.trashItem(at: u, resultingItemURL: nil) }
        playTrashSound()
        return .message(urls.count == 1 ? "Moved \(urls[0].lastPathComponent) to Trash" : "Moved \(urls.count) items to Trash")
    }

    static func share(_ urls: [URL]) throws -> Outcome {
        let anchor = NSPanel(contentRect: NSRect(origin: NSEvent.mouseLocation, size: NSSize(width: 2, height: 2)),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        anchor.isOpaque = false
        anchor.backgroundColor = .clear
        anchor.level = .popUpMenu
        anchor.isReleasedWhenClosed = false
        anchor.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        let picker = NSSharingServicePicker(items: urls)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            picker.show(relativeTo: .zero, of: anchor.contentView!, preferredEdge: .minY)
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { anchor.orderOut(nil) }
        }
        return .none
    }

    static func reveal(_ urls: [URL]) throws -> Outcome { NSWorkspace.shared.activateFileViewerSelecting(urls); return .none }

    // MARK: actions on a folder (right-click on empty space)

    static func newFolder(in folder: URL) throws -> Outcome {
        let src = """
        tell application "Finder"
            activate
            set f to make new folder at (POSIX file \(quoted(folder.path)) as alias)
            select f
        end tell
        """
        script("newfolder-\(folder.path)", src)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { postKey(36) }
        return .none
    }

    static func paste() throws -> Outcome { activateFinder { postKey(9, flags: .maskCommand) }; return .none }      // ⌘V
    static func viewOptions() throws -> Outcome { activateFinder { postKey(38, flags: .maskCommand) }; return .none } // ⌘J
    static func selectAll() throws -> Outcome { activateFinder { postKey(0, flags: .maskCommand) }; return .none }    // ⌘A
    static func cleanUp() throws -> Outcome {
        script("cleanup", "tell application \"Finder\"\nactivate\ntry\nclean up front window\nend try\nend tell")
        return .none
    }

    // MARK: wheel items

    static func items(urls: [URL], folder: URL?) -> [WheelItem] {
        if urls.isEmpty {
            let f = folder ?? desktop
            return [
                WheelItem("New Folder", "Create a new folder here", symbol: "folder.badge.plus", onMain: true) { _ in try newFolder(in: f) },
                WheelItem("Paste", "Paste items here", symbol: "doc.on.clipboard", onMain: true) { _ in try paste() },
                WheelItem("Get Info", "Show info for \(f.lastPathComponent)", symbol: "info.circle", onMain: true) { _ in try getInfo([f]) },
                WheelItem("Select All", "Select everything here", symbol: "checkmark.circle", onMain: true) { _ in try selectAll() },
                WheelItem("View", "Show view options", symbol: "slider.horizontal.3", onMain: true) { _ in try viewOptions() },
                WheelItem("Clean Up", "Clean up icons", symbol: "square.grid.3x3", onMain: true) { _ in try cleanUp() },
                WheelItem("Terminal", "Open this folder in Terminal", symbol: "terminal", onMain: true) { _ in try Actions.terminal([f]) },
                WheelItem("Convert", "Choose files to convert", symbol: "arrow.triangle.2.circlepath", onMain: true) { _ in
                    (NSApp.delegate as? AppDelegate)?.pickFiles(); return .none
                },
            ]
        }
        let one = urls.count == 1
        return [
            WheelItem("Open", one ? "Open \(urls[0].lastPathComponent)" : "Open \(urls.count) items", symbol: "arrow.up.forward.app", onMain: true) { try open($0) },
            WheelItem("Quick Look", "Preview with Quick Look", symbol: "eye", onMain: true) { try quickLook($0) },
            WheelItem("Get Info", "Show the Info window", symbol: "info.circle", onMain: true) { try getInfo($0) },
            WheelItem("Rename", "Rename in Finder", symbol: "pencil", onMain: true) { try rename($0) },
            WheelItem("Duplicate", "Duplicate next to the original", symbol: "plus.square.on.square") { try Actions.duplicate($0) },
            WheelItem("Copy", "Copy to the clipboard", symbol: "doc.on.doc", onMain: true) { try Actions.copy($0) },
            WheelItem("Share", "Share with AirDrop, Mail, Messages…", symbol: "square.and.arrow.up", onMain: true) { try share($0) },
            WheelItem("Trash", one ? "Move \(urls[0].lastPathComponent) to the Trash" : "Move \(urls.count) items to the Trash", symbol: "trash", onMain: true) { try trash($0) },
        ]
    }
}
