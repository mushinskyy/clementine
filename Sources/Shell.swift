import AppKit
import SwiftUI

/// Entry points used by Finder: the Finder Sync extension talks to us over the
/// `clementine://` URL scheme, and the Services menu calls `ServiceProvider`.
enum ShellBridge {
    static func handle(_ url: URL) {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let q = c.queryItems ?? []
        let paths = q.filter { $0.name == "path" }.compactMap(\.value)
        let urls = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { Toast.show("No files were selected", style: .error); return }
        let wheel = q.first { $0.name == "wheel" }?.value ?? "pick"
        let item = q.first { $0.name == "item" }?.value ?? ""
        if wheel == "pick" || c.host == "pick" { OptionPicker.show(urls) } else { run(wheel: wheel, item: item, urls: urls) }
    }

    static func run(wheel: String, item title: String, urls: [URL]) {
        guard let kind = WheelKind(rawValue: wheel) else { OptionPicker.show(urls); return }
        let items = ItemBuilder.items(for: kind, urls: urls)
        guard let item = items.first(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame }) else {
            Toast.show("\"\(title)\" isn't available for these files", style: .error)
            return
        }
        Runner.run(item, urls: urls)
    }
}

final class ServiceProvider: NSObject {
    private func urls(from pboard: NSPasteboard) -> [URL] {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (pboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL]) ?? []
    }

    @objc func openPicker(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let u = urls(from: pboard)
        guard !u.isEmpty else { error.pointee = "No files selected"; return }
        OptionPicker.show(u)
    }

    /// userData is "<wheel>:<item title>", e.g. "convert:PNG".
    @objc func runItem(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let u = urls(from: pboard)
        guard !u.isEmpty else { error.pointee = "No files selected"; return }
        let parts = (userData ?? "").split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { OptionPicker.show(u); return }
        ShellBridge.run(wheel: parts[0], item: parts[1], urls: u)
    }
}

// MARK: - Picker window (click instead of drop)

enum OptionPicker {
    static func show(_ urls: [URL]) {
        WheelController.shared.showClickable(.convert, urls: urls, folder: nil, at: NSEvent.mouseLocation)
    }
}

struct PickerView: View {
    let urls: [URL]
    @State private var tab: WheelKind = .convert
    @State private var items: [WheelItem] = []
    @Environment(\.editorWindow) private var window

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: urls[0].path)).resizable().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items").font(.headline).lineLimit(1).truncationMode(.middle)
                    Text(urls.count == 1 ? urls[0].deletingLastPathComponent().path : urls.map(\.lastPathComponent).joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
            }
            .padding(.top, 8)

            SwiftUI.Picker("", selection: $tab) {
                ForEach(WheelKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(items.indices, id: \.self) { i in
                        let item = items[i]
                        Button { choose(item) } label: {
                            VStack(spacing: 6) {
                                if let s = item.symbol {
                                    Image(systemName: s).font(.system(size: 22, weight: .medium)).frame(height: 28)
                                } else {
                                    Text(item.title).font(.system(size: 17, weight: .bold)).frame(height: 28)
                                }
                                if item.symbol != nil { Text(item.title).font(.subheadline.weight(.semibold)) }
                                Text(item.caption).font(.caption).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 92)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 8)
            }
            if items.isEmpty {
                Text("Nothing to do with these files.").foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 600, height: 560)
        .onAppear { reload() }
        .onChange(of: tab) { _ in reload() }
    }

    private func reload() { items = ItemBuilder.items(for: tab, urls: urls) }

    private func choose(_ item: WheelItem) {
        window?.window?.close()
        Runner.run(item, urls: urls)
    }
}
