import SwiftUI
import AppKit

public struct AbletonChannelPluginRunnerView: View {
    @StateObject private var engine = AbletonChannelMacroEngine.shared
    @EnvironmentObject private var store: AppStore

    private let presetPlugins = [
        "Utility",
        "EQ Eight",
        "Pro-Q 3",
        "Compressor",
        "Glue Compressor",
        "Limiter",
        "Saturator",
        "SPAN"
    ]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerSection
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.sidebarBg.opacity(0.85))

            Divider().background(Color.divider)

            // Main Content Scrollable
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Status Banners (Live running, Accessibility permission)
                    statusBannersSection

                    // Track Selection Section (CHOOSE TRACKS)
                    trackSelectionSection

                    // Automation Method (Clipboard vs Search)
                    methodSection

                    // Live View & Direction
                    directionSection

                    // Search details if in Search mode
                    if engine.mode == .searchAndInsert {
                        searchDetailsSection
                    }

                    // Pacing Speed
                    pacingSection

                    // Helpful Tips Box
                    proTipSection
                }
                .padding(20)
            }

            Divider().background(Color.divider)

            // Bottom Action Footer
            footerSection
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.sidebarBg.opacity(0.85))
        }
        .frame(minWidth: 490, idealWidth: 520, maxWidth: 580, minHeight: 600, idealHeight: 680)
        .background(Color.appBg)
        .onAppear {
            engine.refreshFromOpenSession(using: store.projects)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Channel Plugin Runner")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primaryText)

                    Text("MACRO")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                }

                Text("Batch automate VSTs & devices across chosen channels in Ableton Live")
                    .font(.system(size: 11))
                    .foregroundColor(.secondaryText)
            }

            Spacer()

            // Ableton Live connection indicator
            HStack(spacing: 5) {
                Circle()
                    .fill(engine.isAbletonRunning ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(engine.isAbletonRunning ? (engine.abletonAppName ?? "Live Active") : "Live Closed")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(engine.isAbletonRunning ? .primaryText : .secondaryText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.elevatedBg, in: Capsule())
            .overlay { Capsule().stroke(Color.subtleBorder, lineWidth: 1) }

            Button {
                engine.refreshFromOpenSession(using: store.projects)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundColor(.secondaryText)
            }
            .buttonStyle(.plain)
            .help("Refresh connected Ableton set & tracks")
        }
    }

    // MARK: - Status Banners

    @ViewBuilder
    private var statusBannersSection: some View {
        if !engine.isAbletonRunning {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ableton Live not detected")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.primaryText)
                    Text("Open your project in Ableton Live. The macro will automate the running session.")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondaryText)
                }
                Spacer()
                Button("Refresh") {
                    engine.refreshFromOpenSession(using: store.projects)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
            .background(Color.orange.opacity(0.08))
            .cornerRadius(8)
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1) }
        }

        if !engine.isAccessibilityTrusted {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 14))
                    .foregroundColor(.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility Permission Recommended")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.primaryText)
                    Text("Allow goodvibrations HQ in System Settings to smoothly send keystrokes to Live.")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondaryText)
                }
                Spacer()
                Button("Open Settings") {
                    engine.openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(12)
            .background(Color.accent.opacity(0.08))
            .cornerRadius(8)
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.accent.opacity(0.25), lineWidth: 1) }
        }
    }

    // MARK: - Track Selection (CHOOSE TRACKS)

    private var trackSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with project name and filters
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CHOOSE TARGET TRACKS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(.tertiaryText)

                    if let name = engine.loadedProjectName {
                        Text(name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primaryText)
                    }
                }

                Spacer()

                // Filter Buttons
                HStack(spacing: 4) {
                    filterButton("All") { engine.selectAllTracks() }
                    filterButton("Audio") { engine.selectAudioTracksOnly() }
                    filterButton("MIDI") { engine.selectMidiTracksOnly() }
                    filterButton("Clear") { engine.deselectAllTracks() }
                }
            }

            // Scrollable List of Tracks with Checkboxes
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(engine.tracks) { track in
                            trackRow(track)
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(Color.surfaceBg)
                .cornerRadius(6)
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(Color.subtleBorder, lineWidth: 1) }
            }

            // Selection summary note
            HStack {
                HStack(spacing: 4) {
                    Text("\(engine.selectedCount) of \(engine.tracks.count) tracks selected")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(engine.selectedCount > 0 ? .accent : .secondaryText)
                }

                Spacer()

                if let first = engine.selectedTracks.first {
                    Text("Starts at #\(first.index) '\(first.name)'")
                        .font(.system(size: 10.5))
                        .foregroundColor(.tertiaryText)
                }
            }
        }
    }

    private func filterButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondaryText)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.elevatedBg, in: RoundedRectangle(cornerRadius: 4))
                .overlay { RoundedRectangle(cornerRadius: 4).stroke(Color.subtleBorder, lineWidth: 0.5) }
        }
        .buttonStyle(.plain)
    }

    private func trackRow(_ track: MacroTrackTarget) -> some View {
        HStack(spacing: 8) {
            // Checkbox
            Image(systemName: track.isSelected ? "checkmark.square.fill" : "square")
                .font(.system(size: 13))
                .foregroundColor(track.isSelected ? .accent : .tertiaryText)

            // Index
            Text("#\(track.index)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.tertiaryText)
                .frame(width: 24, alignment: .leading)

            // Track color bar
            RoundedRectangle(cornerRadius: 1)
                .fill(track.color)
                .frame(width: 3.5, height: 16)

            // Track type icon
            Image(systemName: track.type.systemIcon)
                .font(.system(size: 10))
                .foregroundColor(track.color)
                .frame(width: 14)

            // Track name
            Text(track.name)
                .font(.system(size: 11.5, weight: track.isSelected ? .semibold : .regular))
                .foregroundColor(track.isSelected ? .primaryText : .secondaryText)
                .lineLimit(1)

            Spacer()

            // Existing plugins badges
            if !track.devices.isEmpty {
                HStack(spacing: 3) {
                    ForEach(track.devices.prefix(3), id: \.self) { devName in
                        Text(devName)
                            .font(.system(size: 8.5))
                            .foregroundColor(.tertiaryText)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 3))
                    }
                    if track.devices.count > 3 {
                        Text("+\(track.devices.count - 3)")
                            .font(.system(size: 8))
                            .foregroundColor(.tertiaryText)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(track.isSelected ? Color.accent.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            engine.toggleTrack(id: track.id)
        }
    }

    // MARK: - Method Section

    private var methodSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AUTOMATION METHOD")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundColor(.tertiaryText)

            VStack(spacing: 6) {
                ForEach(ChannelMacroMode.allCases) { mode in
                    let isSelected = engine.mode == mode
                    Button {
                        engine.mode = mode
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 14))
                                .foregroundColor(isSelected ? .accent : .tertiaryText)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.rawValue)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(isSelected ? .primaryText : .secondaryText)
                                Text(mode.subtitle)
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.tertiaryText)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? Color.accent.opacity(0.12) : Color.surfaceBg)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? Color.accent.opacity(0.4) : Color.subtleBorder, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Direction

    private var directionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LIVE VIEW & NAVIGATION")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundColor(.tertiaryText)

            Picker("Direction", selection: $engine.direction) {
                ForEach(ChannelMacroDirection.allCases) { dir in
                    Text(dir.rawValue).tag(dir)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Search Details (When in search mode)

    private var searchDetailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DEVICE TO SEARCH & INSERT")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundColor(.tertiaryText)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.tertiaryText)
                TextField("Device or plugin name (e.g. Utility, Pro-Q 3)", text: $engine.pluginSearchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.surfaceBg)
            .cornerRadius(6)
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(Color.subtleBorder, lineWidth: 1) }

            // Preset chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(presetPlugins, id: \.self) { preset in
                        Button {
                            engine.pluginSearchQuery = preset
                        } label: {
                            Text(preset)
                                .font(.system(size: 10.5, weight: engine.pluginSearchQuery == preset ? .semibold : .regular))
                                .foregroundColor(engine.pluginSearchQuery == preset ? .white : .secondaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(engine.pluginSearchQuery == preset ? Color.accent.opacity(0.8) : Color.surfaceBg)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.subtleBorder, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Pacing

    private var pacingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PACING SPEED")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(.tertiaryText)
                Spacer()
                Text("Delay between channel switches")
                    .font(.system(size: 10))
                    .foregroundColor(.tertiaryText)
            }

            Picker("Pacing", selection: $engine.pacing) {
                ForEach(ChannelMacroPacing.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Pro Tip

    private var proTipSection: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 13))
                .foregroundColor(.yellow)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text("How this works seamlessly in Ableton:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primaryText)

                Text("1. In Ableton Live, copy your desired plugin (⌘C on the device header).\n2. Select your first target track in Live.\n3. Click 'Run Macro' below — goodvibrations HQ will paste on each checked track and skip unchecked ones.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceBg.opacity(0.8))
        .cornerRadius(8)
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.subtleBorder, lineWidth: 1) }
    }

    // MARK: - Footer & Action

    private var footerSection: some View {
        VStack(spacing: 10) {
            if engine.isRunning {
                // Running Progress View
                VStack(spacing: 8) {
                    HStack {
                        if let count = engine.countdownRemaining {
                            Text("⏳ Starting in \(count)…")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.accent)
                        } else if let trackName = engine.currentProcessingTrack {
                            Text("Processing: \(trackName)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.accent)
                        }
                    }

                    HStack {
                        Text(engine.statusMessage)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primaryText)
                            .lineLimit(1)

                        Spacer()

                        Button("Stop (Esc)") {
                            engine.stopMacro()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                        .keyboardShortcut(.escape, modifiers: [])
                    }
                }
            } else {
                // Idle Run Button
                HStack(spacing: 12) {
                    if let summary = engine.lastRunSummary {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(summary)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondaryText)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Button {
                        engine.startMacro()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text(engine.selectedCount > 0 ? "Run on \(engine.selectedCount) Tracks" : "Select Tracks First")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .background(engine.selectedCount > 0 ? Color.accent : Color.gray, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(engine.selectedCount == 0)
                    .keyboardShortcut("p", modifiers: [.command, .option])
                }
            }
        }
    }
}
