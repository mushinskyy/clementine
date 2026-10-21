import AppKit

/// Watches for system-wide drag sessions without needing any privacy permissions:
/// it polls the mouse button state, the drag pasteboard and the modifier keys.
final class DragMonitor {
    static let shared = DragMonitor()

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard(name: .drag).changeCount
    private var draggedURLs: [URL]?
    private var prevFlags: NSEvent.ModifierFlags = []
    private var wasDown = false

    func start() {
        let t = Timer(timeInterval: 1.0 / 40.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let down = (NSEvent.pressedMouseButtons & 1) != 0
        if down {
            let pb = NSPasteboard(name: .drag)
            let cc = pb.changeCount
            if cc != lastChangeCount {
                lastChangeCount = cc
                draggedURLs = nil
                if !WheelController.shared.isOwnDrag {
                    let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
                    if let urls = pb.readObjects(forClasses: [NSURL.self], options: opts) as? [URL], !urls.isEmpty {
                        draggedURLs = urls
                        prevFlags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    }
                }
            }
            if let urls = draggedURLs { checkModifiers(urls) }
        } else {
            if wasDown, draggedURLs != nil {
                draggedURLs = nil
                WheelController.shared.dragEnded()
            }
            prevFlags = []
        }
        wasDown = down
    }

    private func checkModifiers(_ urls: [URL]) {
        guard Prefs.shared.dragWheels else { return }
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let newlyPressed = flags.subtracting(prevFlags)
        prevFlags = flags
        guard !newlyPressed.isEmpty else { return }
        for kind in WheelKind.allCases {
            if let f = Prefs.shared.key(for: kind).flag, newlyPressed.contains(f) {
                WheelController.shared.show(kind, urls: urls, at: NSEvent.mouseLocation)
                return
            }
        }
    }
}
