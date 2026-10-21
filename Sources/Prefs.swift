import AppKit
import Combine
import ServiceManagement

enum ModKey: String, CaseIterable, Identifiable {
    case shift, command, control, option, none
    var id: String { rawValue }
    var flag: NSEvent.ModifierFlags? {
        switch self {
        case .shift: return .shift
        case .command: return .command
        case .control: return .control
        case .option: return .option
        case .none: return nil
        }
    }
    var symbol: String {
        switch self {
        case .shift: return "⇧"
        case .command: return "⌘"
        case .control: return "⌃"
        case .option: return "⌥"
        case .none: return "–"
        }
    }
    var label: String {
        switch self {
        case .shift: return "⇧ Shift"
        case .command: return "⌘ Command"
        case .control: return "⌃ Control"
        case .option: return "⌥ Option"
        case .none: return "Off"
        }
    }
}

enum WheelKind: String, CaseIterable, Identifiable {
    case finder, convert, tools, actions
    var id: String { rawValue }
    var title: String {
        switch self {
        case .finder: return "Finder"
        case .convert: return "Convert"
        case .tools: return "Tools"
        case .actions: return "Actions"
        }
    }
    var symbol: String {
        switch self {
        case .finder: return "macwindow"
        case .convert: return "arrow.triangle.2.circlepath"
        case .tools: return "wrench.and.screwdriver.fill"
        case .actions: return "paperplane.fill"
        }
    }
}

enum OutputLocation: String, CaseIterable, Identifiable {
    case sameFolder, desktop, downloads
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sameFolder: return "Next to the original"
        case .desktop: return "Desktop"
        case .downloads: return "Downloads"
        }
    }
    var directory: URL? {
        let fm = FileManager.default
        switch self {
        case .sameFolder: return nil
        case .desktop: return fm.urls(for: .desktopDirectory, in: .userDomainMask).first
        case .downloads: return fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
        }
    }
}

final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    @Published var convertKey: ModKey { didSet { d.set(convertKey.rawValue, forKey: "convertKey") } }
    @Published var toolsKey: ModKey { didSet { d.set(toolsKey.rawValue, forKey: "toolsKey") } }
    @Published var actionsKey: ModKey { didSet { d.set(actionsKey.rawValue, forKey: "actionsKey") } }
    @Published var output: OutputLocation { didSet { d.set(output.rawValue, forKey: "output") } }
    @Published var dragWheels: Bool { didSet { d.set(dragWheels, forKey: "dragWheels") } }
    @Published var takeover: Bool { didSet { d.set(takeover, forKey: "takeover"); RightClickTakeover.shared.reconcile() } }
    @Published var firstWheel: String { didSet { d.set(firstWheel, forKey: "firstWheel") } }
    @Published var showToast: Bool { didSet { d.set(showToast, forKey: "showToast") } }
    @Published var playSound: Bool { didSet { d.set(playSound, forKey: "playSound") } }
    @Published var launchAtLogin: Bool { didSet { d.set(launchAtLogin, forKey: "launchAtLogin"); applyLaunchAtLogin() } }
    var welcomed: Bool {
        get { d.bool(forKey: "welcomed") }
        set { d.set(newValue, forKey: "welcomed") }
    }

    private init() {
        convertKey = ModKey(rawValue: d.string(forKey: "convertKey") ?? "") ?? .shift
        toolsKey = ModKey(rawValue: d.string(forKey: "toolsKey") ?? "") ?? .command
        actionsKey = ModKey(rawValue: d.string(forKey: "actionsKey") ?? "") ?? .control
        output = OutputLocation(rawValue: d.string(forKey: "output") ?? "") ?? .sameFolder
        dragWheels = d.object(forKey: "dragWheels") as? Bool ?? true
        takeover = d.object(forKey: "takeover") as? Bool ?? true
        firstWheel = d.string(forKey: "firstWheel") ?? "finder"
        showToast = d.object(forKey: "showToast") as? Bool ?? true
        playSound = d.object(forKey: "playSound") as? Bool ?? true
        launchAtLogin = d.bool(forKey: "launchAtLogin")
    }

    func key(for kind: WheelKind) -> ModKey {
        switch kind {
        case .finder: return .none
        case .convert: return convertKey
        case .tools: return toolsKey
        case .actions: return actionsKey
        }
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Toast.show("Launch at login: \(error.localizedDescription)", style: .error)
        }
    }
}
