import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var globalHotkey: GlobalHotkeyManager
    @EnvironmentObject var dragScroll: AbletonDragScrollManager
    @StateObject private var launchAtLogin = LaunchAtLoginManager()

    var body: some View {
        Form {

            // MARK: Appearance
            Section {
                Picker("Appearance", selection: $settings.appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Project List Display", selection: $settings.showInlineWaveforms) {
                    Label("Inline Waveforms", systemImage: "waveform").tag(true)
                    Label("Icons & Artwork", systemImage: "photo").tag(false)
                }
                .pickerStyle(.segmented)
                Text("Show inline audio waveforms with quick-play buttons for bounced tracks, like DAWbro.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Appearance", systemImage: "paintbrush")
                    .font(.headline)
            }

            Divider()

            Section {
                ForEach(StreamingService.allCases, id: \.self) { service in
                    HStack {
                        Label(service.title, systemImage: service.icon)
                        Spacer()
                        Text("Uses provider app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open") { NSWorkspace.shared.open(service.homeURL) }
                    }
                }

                Text("Sign in and out in the official music app. HQ does not claim or store account connection state.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Music Accounts", systemImage: "person.crop.circle")
                    .font(.headline)
            }

            Divider()

            // MARK: Startup
            Section {
                Toggle("Launch goodvibrations HQ at Login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .disabled(launchAtLogin.isChanging)

                if let message = launchAtLogin.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Keeps Quick Access available in the menu bar after you restart your Mac.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Label("Startup", systemImage: "power")
                    .font(.headline)
            }

            Divider()

            // MARK: Ableton Export Hotkey
            Section {
                Toggle("Enable F1 global hotkey", isOn: $globalHotkey.isEnabled)

                Text("While goodvibrations HQ is running, press **F1** anywhere (including inside Ableton Live) to auto-version and export the active project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let result = globalHotkey.lastResult {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: result.contains("success") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(result.contains("success") ? .green : .orange)
                            .font(.caption)
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            } header: {
                Label("Ableton Export Hotkey", systemImage: "keyboard")
                    .font(.headline)
            }

            Divider()

            // MARK: Ableton Drag Navigation (W/S)
            Section {
                Toggle("Drag-scroll tracks with W and S", isOn: $dragScroll.isEnabled)

                Text("While dragging a track, clip, or sample in Ableton Live (mouse held down), press **W** to scroll up (Page Up) and **S** to scroll down (Page Down). Normal typing in Ableton search and other apps is never interrupted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Ableton Drag Navigation", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.headline)
            }

            Divider()
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Music Folder")
                            .font(.system(size: 13, weight: .medium))
                        Text(store.rootFolderURL?.path ?? "Not set")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Change…") { store.selectFolder() }
                }

                HStack {
                    Text("Default sort")
                    Spacer()
                    Picker("", selection: $store.sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
            } header: {
                Label("Library", systemImage: "folder")
                    .font(.headline)
            }

            Divider()

            // MARK: Sidebar
            Section {
                HStack {
                    Text("Sidebar width")
                    Spacer()
                    Slider(value: $settings.sidebarWidth, in: 190...440, step: 1)
                        .frame(width: 160)
                    Text("\(Int(settings.sidebarWidth)) pt")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 46, alignment: .trailing)
                }
            } header: {
                Label("Layout", systemImage: "sidebar.left")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding(.vertical, 8)
        .preferredColorScheme(settings.appearanceMode.colorSchemeOverride)
        .onAppear {
            launchAtLogin.refresh()
        }
    }

}

extension StreamingService: Identifiable {
    var id: String { rawValue }

    var homeURL: URL {
        switch self {
        case .spotify: return URL(string: "https://open.spotify.com")!
        case .appleMusic: return URL(string: "https://music.apple.com")!
        }
    }
}
