import SwiftUI

struct SettingsView: View {
    @ObservedObject var p = Prefs.shared
    @State private var trusted = RightClickTakeover.shared.isTrusted
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Right-click in Finder") {
                Toggle("Replace Finder's right-click menu with the wheel", isOn: $p.takeover)
                Picker("First wheel shown", selection: $p.firstWheel) {
                    Text("Finder actions").tag("finder")
                    Text("Convert formats").tag("convert")
                }
                HStack {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trusted ? Color.green : Color.orange)
                    Text(trusted ? "Accessibility access granted" : "Needs Accessibility access to intercept right-clicks")
                    Spacer()
                    if !trusted {
                        Button("Grant…") {
                            RightClickTakeover.shared.requestPermission()
                            RightClickTakeover.shared.openAccessibilitySettings()
                        }
                    }
                }
                Text("Hold Option while right-clicking for Finder's normal menu. Tab or ⇧ ⌘ ⌃ switch wheels, Esc closes. The wheel is also available from Finder's Quick Actions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Dragging") {
                Toggle("Also show wheels while dragging files", isOn: $p.dragWheels)
            }
            Section("Drag keys") {
                keyPicker("Convert formats", $p.convertKey)
                keyPicker("File tools", $p.toolsKey)
                keyPicker("File actions", $p.actionsKey)
                Text("Start dragging a file, then tap the key. Tap it again to see more options.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Output") {
                Picker("Save converted files", selection: $p.output) {
                    ForEach(OutputLocation.allCases) { Text($0.label).tag($0) }
                }
                Text("Originals are never changed. Existing files are never overwritten.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("General") {
                Toggle("Show a notice when a file is ready", isOn: $p.showToast)
                Toggle("Play a sound", isOn: $p.playSound)
                Toggle("Launch at login", isOn: $p.launchAtLogin)
                Text(FF.available ? "ffmpeg is bundled: \(FF.version ?? "ready") — MKV, WebM, MP3, OGG, Opus and WebP are enabled." : "ffmpeg not found: MKV, WebM, MP3, OGG and Opus are unavailable.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
        .onReceive(tick) { _ in trusted = RightClickTakeover.shared.isTrusted }
    }

    private func keyPicker(_ label: String, _ sel: Binding<ModKey>) -> some View {
        Picker(label, selection: sel) {
            ForEach(ModKey.allCases) { Text($0.label).tag($0) }
        }
    }
}

struct WelcomeView: View {
    @ObservedObject var p = Prefs.shared
    var onDone: () -> Void
    @State private var trusted = RightClickTakeover.shared.isTrusted
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                Text("Clementine").font(.largeTitle.weight(.bold))
                Text("Right-click. Convert. Done.").foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                card("🍊", "Right-click in Finder", "The wheel replaces Finder's menu: Finder actions, format conversions, tools and file actions, one click away. Hold Option for the normal menu.")
                card("⇥", "Switch wheels", "Click the tabs above the wheel, press Tab, or tap \(p.convertKey.label), \(p.toolsKey.label) or \(p.actionsKey.label). Esc closes.")
                HStack(spacing: 12) {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "hand.raised.fill").font(.title2)
                        .foregroundStyle(trusted ? Color.green : accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(trusted ? "Accessibility access granted" : "Allow Accessibility access").font(.headline)
                        Text(trusted ? "Right-click interception is active." : "macOS requires it to intercept right-clicks. Click Grant, then enable Clementine in the list.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if !trusted {
                        Button("Grant…") {
                            RightClickTakeover.shared.requestPermission()
                            RightClickTakeover.shared.openAccessibilitySettings()
                        }.buttonStyle(.borderedProminent).tint(accent)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
            }
            Text("Everything runs on your Mac. Nothing is uploaded.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Got it") { onDone() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(accent)
        }
        .padding(28)
        .frame(width: 460)
        .onReceive(tick) { _ in trusted = RightClickTakeover.shared.isTrusted }
    }

    private func card(_ key: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(key).font(.system(size: 22, weight: .semibold)).frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
    }
}
