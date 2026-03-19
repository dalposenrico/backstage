import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: SettingsStore

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

            // MARK: Library
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
    }
}
