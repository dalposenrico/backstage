import SwiftUI
import AppKit

public struct AbletonChannelPluginRunnerView: View {
    @StateObject private var engine = AbletonChannelMacroEngine.shared
    @EnvironmentObject private var store: AppStore
    @State private var projectTrackCount: Int? = nil

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

    private let channelCountPresets = [4, 8, 12, 16, 24, 32]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerSection
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.sidebarBg.opacity(0.85))

            Divider().background(Color.divider)

            // Main Content Scrollable
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Live Status & Permission Banner
                    statusBannersSection

                    // Mode Selection
                    modeSelectionSection

                    // Target View & Direction
                    directionSection

                    // Number of Channels
                    channelCountSection

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
        .frame(minWidth: 460, idealWidth: 490, maxWidth: 540, minHeight: 520, idealHeight: 590)
        .background(Color.appBg)
        .onAppear {
            engine.checkEnvironment()
            if let project = store.selectedProject,
               let alsUrl = project.newestAbletonVersion?.url ?? project.versions.first?.url {
                Task.detached(priority: .background) {
                    if let parsed = AbletonArrangementParser.parse(from: alsUrl) {
                        let count = parsed.tracks.count
                        await MainActor.run {
                            self.projectTrackCount = count
                        }
                    }
                }
            }
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

                Text("Batch automate VSTs & devices across tracks in your open Live set")
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
                    engine.checkEnvironment()
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

    // MARK: - Mode Selection

    private var modeSelectionSection: some View {
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

    // MARK: - Channels Count

    private var channelCountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HOW MANY CHANNELS?")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(.tertiaryText)

                Spacer()

                Text("\(engine.channelCount) channels selected")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.accent)
            }

            // Quick presets
            HStack(spacing: 6) {
                ForEach(channelCountPresets, id: \.self) { count in
                    let isSelected = engine.channelCount == count
                    Button {
                        engine.channelCount = count
                    } label: {
                        Text("\(count)")
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? .white : .secondaryText)
                            .frame(width: 32, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(isSelected ? Color.accent : Color.surfaceBg)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(isSelected ? Color.accent : Color.subtleBorder, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }

                // If user has a current project in goodvibrations HQ with parsed tracks
                if let project = store.selectedProject,
                   let trackCount = projectTrackCount,
                   trackCount > 0 {
                    Button {
                        engine.channelCount = trackCount
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 9))
                            Text("Current '\(project.name)' (\(trackCount))")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundColor(engine.channelCount == trackCount ? .white : .secondaryText)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(engine.channelCount == trackCount ? Color.accent : Color.surfaceBg)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(engine.channelCount == trackCount ? Color.accent : Color.subtleBorder, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // Stepper slider for custom numbers
            HStack(spacing: 12) {
                Slider(value: Binding(
                    get: { Double(engine.channelCount) },
                    set: { engine.channelCount = Int($0) }
                ), in: 1...64, step: 1)

                Stepper("", value: $engine.channelCount, in: 1...128)
                    .labelsHidden()
            }
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

                Text("1. In Ableton, copy your desired plugin (⌘C on the device header).\n2. Select your first channel in Live.\n3. Hit 'Run Macro' below — goodvibrations HQ will automatically switch to Live and duplicate the plugin down your channels.")
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
                        } else {
                            ProgressView(value: Double(engine.currentChannel), total: Double(max(1, engine.channelCount)))
                                .tint(.accent)
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
                            Text("Run Macro on Live")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .background(Color.accent, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(!engine.isAbletonRunning && false) // Allow running even if not detected yet
                    .keyboardShortcut("p", modifiers: [.command, .option])
                }
            }
        }
    }
}
