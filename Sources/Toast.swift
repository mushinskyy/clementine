import AppKit

/// A small floating notice near the top of the screen. No notification permission needed.
final class Toast {
    enum Style { case working, success, error }

    static let shared = Toast()
    private let panel: NSPanel
    private let icon = NSImageView()
    private let spinner = NSProgressIndicator()
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?
    private var revealURL: URL?

    private init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 44), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false

        let content = ClickView()
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.94).cgColor
        content.layer?.cornerRadius = 12
        content.onClick = { [weak self] in
            if let u = self?.revealURL { NSWorkspace.shared.activateFileViewerSelecting([u]) }
            self?.hideNow()
        }
        panel.contentView = content

        icon.translatesAutoresizingMaskIntoConstraints = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.appearance = NSAppearance(named: .darkAqua)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        content.addSubview(icon); content.addSubview(spinner); content.addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20), icon.heightAnchor.constraint(equalToConstant: 20),
            spinner.centerXAnchor.constraint(equalTo: icon.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
    }

    static func show(_ text: String, style: Style, sticky: Bool = false, reveal: URL? = nil) {
        guard Prefs.shared.showToast || style == .error else { return }
        DispatchQueue.main.async { shared.present(text, style: style, sticky: sticky, reveal: reveal) }
    }

    static func hide() { DispatchQueue.main.async { shared.hideNow() } }

    private func present(_ text: String, style: Style, sticky: Bool, reveal: URL?) {
        hideWork?.cancel()
        revealURL = reveal
        label.stringValue = text
        switch style {
        case .working:
            icon.isHidden = true; spinner.isHidden = false; spinner.startAnimation(nil)
        case .success:
            spinner.stopAnimation(nil); spinner.isHidden = true; icon.isHidden = false
            icon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 16, weight: .semibold))?
                .tinted(NSColor.controlAccentColor)
        case .error:
            spinner.stopAnimation(nil); spinner.isHidden = true; icon.isHidden = false
            icon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 16, weight: .semibold))?
                .tinted(NSColor.systemYellow)
        }
        let width = min(max(label.intrinsicContentSize.width + 70, 200), 520)
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
        let f = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        panel.setFrame(NSRect(x: f.midX - width / 2, y: f.maxY - 60, width: width, height: 44), display: true)
        panel.orderFrontRegardless()
        if !sticky {
            let w = DispatchWorkItem { [weak self] in self?.hideNow() }
            hideWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + (style == .error ? 6 : 3.5), execute: w)
        }
    }

    private func hideNow() {
        hideWork?.cancel()
        spinner.stopAnimation(nil)
        panel.orderOut(nil)
    }
}

final class ClickView: NSView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
}
