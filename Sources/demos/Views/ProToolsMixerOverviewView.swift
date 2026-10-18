import SwiftUI

enum MixerTrackFilter: String, CaseIterable, Identifiable {
    case all = "All Tracks"
    case audio = "Audio"
    case midi = "MIDI"
    case groups = "Groups"
    case returnsAndMaster = "Returns & Master"

    var id: String { rawValue }

    var systemIcon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .audio: return "waveform"
        case .midi: return "pianokeys"
        case .groups: return "folder"
        case .returnsAndMaster: return "slider.vertical.3"
        }
    }
}

struct ProToolsMixerOverviewView: View {
    let arrangement: AbletonArrangement
    let project: Project
    let onReloadArrangement: () -> Void

    @StateObject private var mixingStore = MixingActionStore.shared
    @State private var selectedFilter: MixerTrackFilter = .all
    @State private var searchQuery: String = ""
    @State private var showBatchModal: Bool = false
    @State private var hoveredTrackId: String? = nil
    @State private var hoveredDeviceId: String? = nil

    private var allConsoleTracks: [AbletonTrack] {
        var list = arrangement.tracks
        list.append(contentsOf: arrangement.returnTracks)
        if let master = arrangement.masterTrack {
            list.append(master)
        }
        return list
    }

    private var filteredTracks: [AbletonTrack] {
        let baseList: [AbletonTrack]
        switch selectedFilter {
        case .all:
            baseList = allConsoleTracks
        case .audio:
            baseList = arrangement.tracks.filter { $0.type == .audio }
        case .midi:
            baseList = arrangement.tracks.filter { $0.type == .midi }
        case .groups:
            baseList = arrangement.tracks.filter { $0.type == .group }
        case .returnsAndMaster:
            var rm = arrangement.returnTracks
            if let master = arrangement.masterTrack { rm.append(master) }
            baseList = rm
        }

        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return baseList
        }

        let query = searchQuery.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return baseList.filter { track in
            track.name.lowercased().contains(query)
                || track.devices.contains { dev in
                    dev.name.lowercased().contains(query)
                        || (dev.vendor?.lowercased().contains(query) ?? false)
                        || dev.type.rawValue.lowercased().contains(query)
                }
        }
    }

    private var totalDeviceCount: Int {
        allConsoleTracks.reduce(0) { $0 + $1.devices.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar
            mixerToolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.sidebarBg.opacity(0.85))

            Divider().background(Color.divider)

            // Mixer Console Channel Grid
            if filteredTracks.isEmpty {
                emptyMixerView
            } else {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(filteredTracks) { track in
                            channelStripView(track)
                        }
                    }
                    .padding(16)
                }
            }

            // Bottom Action Status Bar
            if let result = mixingStore.lastActionResult {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.accent)
                    Text(result)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primaryText)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.elevatedBg)
                .overlay(alignment: .top) { Divider().background(Color.divider) }
            }
        }
        .background(Color.appBg)
        .sheet(isPresented: $showBatchModal) {
            BatchPluginModalView(project: project) {
                onReloadArrangement()
            }
        }
    }

    // MARK: - Toolbar

    private var mixerToolbar: some View {
        HStack(spacing: 12) {
            // Eyebrow & Stats
            HStack(spacing: 6) {
                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accent)
                Text("MIXER & INSERTS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(.primaryText)
                Text("\(totalDeviceCount) plugins")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.tertiaryText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.elevatedBg, in: Capsule())
            }

            Divider().frame(height: 18).background(Color.divider)

            // Track Filters
            HStack(spacing: 4) {
                ForEach(MixerTrackFilter.allCases) { filter in
                    let isSelected = selectedFilter == filter
                    Button {
                        selectedFilter = filter
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: filter.systemIcon)
                                .font(.system(size: 9))
                            Text(filter.rawValue)
                                .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                        }
                        .foregroundColor(isSelected ? .white : .secondaryText)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(isSelected ? Color.accent.opacity(0.85) : Color.elevatedBg.opacity(0.6))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 8)

            // Plugin Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(.tertiaryText)
                TextField("Search plugins or tracks...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(width: 170)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.surfaceBg)
            .cornerRadius(6)
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(Color.subtleBorder, lineWidth: 1) }

            // Action: Batch Add Plugins
            Button {
                showBatchModal = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus.square.dashed")
                        .font(.system(size: 10, weight: .bold))
                    Text("Batch Insert")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .frame(height: 25)
                .background(Color.accent, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help("Batch insert plugins across all or selected channels")

            // Action: Mixing Macros Menu
            Menu {
                Text("MIXING SCRIPTS & MACROS").font(.system(size: 9))
                ForEach(mixingStore.customActions) { action in
                    Button {
                        mixingStore.executeAction(action)
                    } label: {
                        Label(action.title, systemImage: action.systemIcon)
                    }
                }
                Divider()
                Button {
                    mixingStore.jumpToAbleton(project: project)
                } label: {
                    Label("Focus Ableton Live", systemImage: "arrow.up.forward.app")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text("Macros")
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .foregroundColor(.secondaryText)
                .padding(.horizontal, 9)
                .frame(height: 25)
                .background(Color.elevatedBg, in: RoundedRectangle(cornerRadius: 5))
                .overlay { RoundedRectangle(cornerRadius: 5).stroke(Color.subtleBorder, lineWidth: 1) }
            }
            .menuStyle(.borderlessButton)
        }
    }

    // MARK: - Channel Strip

    private func channelStripView(_ track: AbletonTrack) -> some View {
        let isHovered = hoveredTrackId == track.id
        let maxSlots = max(6, track.devices.count + 2)

        return VStack(spacing: 0) {
            // Track Header
            VStack(spacing: 4) {
                // Ableton Track Color Strip
                Rectangle()
                    .fill(track.color)
                    .frame(height: 4)

                HStack(spacing: 4) {
                    Image(systemName: track.type.systemIcon)
                        .font(.system(size: 9))
                        .foregroundColor(track.color)
                    Text(track.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primaryText)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.top, 4)

                Text(track.type.rawValue.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(.tertiaryText)
                    .padding(.bottom, 6)
            }
            .frame(width: 136)
            .background(Color.sidebarBg.opacity(isHovered ? 0.95 : 0.7))
            .onHover { hovered in
                hoveredTrackId = hovered ? track.id : nil
            }
            .onTapGesture {
                mixingStore.jumpToAbleton(project: project, trackName: track.name)
            }
            .help("Click to focus track '\(track.name)' in Ableton Live")

            Divider().background(Color.divider)

            // Inserts Rack (Slots 1 through N)
            VStack(spacing: 4) {
                ForEach(0..<maxSlots, id: \.self) { slotIndex in
                    if slotIndex < track.devices.count {
                        let device = track.devices[slotIndex]
                        deviceSlotView(device, track: track, slotIndex: slotIndex)
                    } else {
                        emptySlotView(slotIndex: slotIndex)
                    }
                }
            }
            .padding(6)
            .background(Color.surfaceBg.opacity(0.4))

            Divider().background(Color.divider)

            // Channel Footer
            HStack {
                Text("\(track.devices.count) FX")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.tertiaryText)
                Spacer()
                Button {
                    mixingStore.jumpToAbleton(project: project, trackName: track.name)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 9))
                        .foregroundColor(.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Jump to this track in Ableton")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.sidebarBg.opacity(0.5))
        }
        .frame(width: 136)
        .background(Color.surfaceBg)
        .cornerRadius(7)
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(isHovered ? track.color.opacity(0.6) : Color.subtleBorder, lineWidth: isHovered ? 1.5 : 1)
        }
    }

    // MARK: - Insert Slot (Occupied)

    private func deviceSlotView(_ device: AbletonDevice, track: AbletonTrack, slotIndex: Int) -> some View {
        let isHovered = hoveredDeviceId == device.id
        let isSearchMatch = !searchQuery.isEmpty && (
            device.name.localizedCaseInsensitiveContains(searchQuery)
            || (device.vendor?.localizedCaseInsensitiveContains(searchQuery) ?? false)
        )

        return Button {
            mixingStore.jumpToAbleton(project: project, trackName: track.name)
        } label: {
            HStack(spacing: 5) {
                // Slot Index Letter (A, B, C... like Pro Tools)
                Text(slotLetter(for: slotIndex))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(device.isEnabled ? .tertiaryText : .tertiaryText.opacity(0.5))
                    .frame(width: 10)

                // Device Name
                Text(device.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(device.isEnabled ? .primaryText : .secondaryText.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 2)

                // Type Badge
                Text(device.type.rawValue)
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundColor(device.isEnabled ? device.type.badgeColor : .secondaryText.opacity(0.5))
                    .padding(.horizontal, 3.5)
                    .padding(.vertical, 1.5)
                    .background(
                        (device.isEnabled ? device.type.badgeColor : Color.gray).opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 2.5)
                    )
            }
            .padding(.horizontal, 6)
            .frame(height: 24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        isSearchMatch
                            ? Color.accent.opacity(0.25)
                            : (isHovered ? Color.elevatedBg : Color.elevatedBg.opacity(0.7))
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        isSearchMatch
                            ? Color.accent
                            : (isHovered ? Color.white.opacity(0.2) : Color.subtleBorder.opacity(0.6)),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { hovered in
            hoveredDeviceId = hovered ? device.id : nil
        }
        .help("\(device.name) (\(device.vendor ?? "Native")) · Click to focus in Live")
    }

    // MARK: - Insert Slot (Empty)

    private func emptySlotView(slotIndex: Int) -> some View {
        HStack(spacing: 5) {
            Text(slotLetter(for: slotIndex))
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.tertiaryText.opacity(0.4))
                .frame(width: 10)

            Rectangle()
                .fill(Color.tertiaryText.opacity(0.12))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 6)
        .frame(height: 24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.clear)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.subtleBorder.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }
    }

    private func slotLetter(for index: Int) -> String {
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N"]
        if index < letters.count {
            return letters[index]
        }
        return "\(index + 1)"
    }

    private var emptyMixerView: some View {
        VStack(spacing: 12) {
            Image(systemName: "slider.vertical.3")
                .font(.system(size: 32))
                .foregroundColor(.tertiaryText)
            Text(searchQuery.isEmpty ? "No tracks found in arrangement" : "No plugins or tracks matched '\(searchQuery)'")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondaryText)
            if !searchQuery.isEmpty {
                Button("Clear Search") {
                    searchQuery = ""
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
