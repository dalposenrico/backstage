import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var checkInAssistant: StudioCheckInAssistant
    @EnvironmentObject var globalHotkey: GlobalHotkeyManager
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

            Section {
                Toggle("Studio check-in reminders", isOn: Binding(
                    get: { checkInAssistant.isEnabled },
                    set: { enabled in
                        if enabled { Task { await checkInAssistant.enable() } }
                        else { checkInAssistant.isEnabled = false }
                    }
                ))

                TextField("Calendar event contains", text: $checkInAssistant.calendarMatch)
                TextField("Required Wi-Fi", text: $checkInAssistant.requiredWiFiName)
                TextField("SAE portal", text: $checkInAssistant.portalURLText)

                HStack {
                    Circle()
                        .fill(checkInAssistant.isOnRequiredWiFi ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(checkInAssistant.currentNetworkName.map { "Currently on \($0)" } ?? "Current Wi-Fi name unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") { Task { await checkInAssistant.refresh() } }
                }

                if let error = checkInAssistant.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                } else {
                    Text("Reminds you every 2 minutes from 10 minutes before until 15 minutes after the booking starts. Marking it checked in stops the reminders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Studio Check-in", systemImage: "checkmark.circle")
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
