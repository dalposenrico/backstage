import AppKit
import SwiftUI

private enum FloatingWidgetFilter: String, CaseIterable {
    case recents = "Recents"
    case favourites = "Favourites"
    case all = "All"
}

struct FloatingWidgetView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var audioPlayer: AudioPlayer
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.openWindow) private var openWindow

    @State private var filter: FloatingWidgetFilter = .recents
    @State private var searchText = ""
    @State private var isHoveringPuck = false

    private var activeProject: Project? {
        store.currentOpenProject ?? store.selectedProject ?? store.recentProjects.first
    }

    private var displayedProjects: [Project] {
        let baseList: [Project]
        switch filter {
        case .recents:
            baseList = store.recentProjects
        case .favourites:
            baseList = store.favouriteProjects
        case .all:
            baseList = store.visibleProjects
        }

        if searchText.isEmpty {
            return baseList
        } else {
            return baseList.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var currentPuckWidth: CGFloat {
        settings.petPuckSize.totalCollapsedWidth(hasIcon: settings.showAppIconOnPuck)
    }

    private var currentPuckHeight: CGFloat {
        settings.petPuckSize.totalCollapsedHeight(hasIcon: settings.showAppIconOnPuck)
    }

    var body: some View {
        Group {
            if settings.isFloatingWidgetCollapsed {
                collapsedPetPuck
            } else {
                expandedHudView
            }
        }
        .ignoresSafeArea()
        .onAppear {
            WindowPresenter.configureFloatingWidget(
                pinned: true,
                collapsed: settings.isFloatingWidgetCollapsed,
                puckSize: settings.petPuckSize.dimension,
                targetWidth: currentPuckWidth,
                targetHeight: currentPuckHeight
            )
            if settings.isFloatingWidgetCollapsed {
                updateCollapsedWindowSize(animated: false)
            }
        }
        .onChange(of: settings.showAppIconOnPuck) {
            updateCollapsedWindowSize(animated: true)
        }
        .onChange(of: settings.petPuckSize) {
            updateCollapsedWindowSize(animated: true)
        }
        .onChange(of: store.currentOpenProject) {
            updateCollapsedWindowSize(animated: true)
        }
        .onChange(of: store.openingAbletonProject) {
            updateCollapsedWindowSize(animated: true)
        }
    }

    private func updateCollapsedWindowSize(animated: Bool) {
        guard settings.isFloatingWidgetCollapsed else { return }
        WindowPresenter.updateFloatingWidgetCollapsedWidth(
            currentPuckWidth,
            height: currentPuckHeight,
            animated: animated
        )
    }

    private var appIconImage: NSImage? {
        if let icon = NSImage(named: NSImage.applicationIconName) {
            return icon
        }
        if let icon = NSApp.applicationIconImage {
            return icon
        }
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let icon = NSImage(contentsOfFile: path) {
            return icon
        }
        return nil
    }

    // MARK: - Collapsed Pet Icon & Dynamic Island Capsule

    private var collapsedPetPuck: some View {
        let size = settings.petPuckSize
        return HStack(spacing: 8) {
            if settings.showAppIconOnPuck {
                puckIconView(size: size)
            }
            puckCapsuleView(size: size)
        }
        .frame(width: currentPuckWidth, height: currentPuckHeight)
        .contentShape(Rectangle())
        .ignoresSafeArea()
        .onHover { isHoveringPuck = $0 }
        .contextMenu {
            Button("Open goodvibrations HQ") {
                openWindow(id: "main-window")
                WindowPresenter.showMainWindow()
            }
            Button("Expand goodvibrations HUD") {
                expandWidget()
            }

            Divider()

            Toggle("Show App Icon", isOn: $settings.showAppIconOnPuck)

            Menu("Pill Size (\(settings.petPuckSize.displayName))") {
                ForEach(PetPuckSize.allCases) { puckSize in
                    Button {
                        settings.petPuckSize = puckSize
                    } label: {
                        HStack {
                            Text(puckSize.title)
                            if settings.petPuckSize == puckSize {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            if let project = activeProject {
                Divider()
                Text(project.name).font(.caption).disabled(true)
                if project.newestAbletonVersion != nil {
                    Button("Open in Ableton Live") {
                        store.openInAbleton(project)
                    }
                }
                if project.sortedTracks.first != nil {
                    Button(audioPlayer.isPlaying ? "Pause Demo" : "Play Demo") {
                        audioPlayer.togglePlayPause()
                    }
                }
            }
            Divider()
            Button("Hide Floating Pill (⇧⌘W)") {
                settings.isFloatingWidgetActive = false
                WindowPresenter.hideFloatingWidget()
            }
        }
        .help(puckHelpText)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: settings.showAppIconOnPuck)
    }

    private func puckIconView(size: PetPuckSize) -> some View {
        ZStack {
            // App Icon
            if let icon = appIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.iconDimension, height: size.iconDimension)
                    .shadow(color: Color.black.opacity(0.35), radius: 5, x: 0, y: 3)
            } else {
                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        Circle()
                            .stroke(Color.accentColor.opacity(0.45), lineWidth: 1.5)
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)

                Image(systemName: "waveform")
                    .font(.system(size: size.iconDimension * 0.42, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }

            // Notification Indicator Dot (top right)
            if store.openingAbletonProject?.phase == .opening {
                Circle()
                    .fill(Color.orange)
                    .frame(width: size.dotSize, height: size.dotSize)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    .shadow(color: Color.orange.opacity(0.5), radius: 3)
                    .offset(x: size.dotOffset.x, y: size.dotOffset.y)
            } else if store.currentOpenProject != nil {
                Circle()
                    .fill(Color.green)
                    .frame(width: size.dotSize, height: size.dotSize)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    .shadow(color: Color.green.opacity(0.4), radius: 3)
                    .offset(x: size.dotOffset.x, y: size.dotOffset.y)
            }

            // Hover Cue
            if isHoveringPuck {
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .fill(Color.black.opacity(0.25))
                    .frame(width: size.iconDimension, height: size.iconDimension)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: size.cueIconSize, weight: .bold))
                    .foregroundStyle(.white)
            }

            // Drag & Click Handler Area
            PetPuckDragArea {
                expandWidget()
            }
        }
        .frame(width: size.dimension, height: size.dimension)
    }

    private func puckCapsuleView(size: PetPuckSize) -> some View {
        let isOpening = store.openingAbletonProject?.phase == .opening
        let isLiveActive = store.currentOpenProject != nil

        let projectName: String = {
            if isOpening {
                return store.openingAbletonProject?.projectName ?? "Ableton Live"
            }
            if let active = store.currentOpenProject {
                return active.name
            }
            return activeProject?.name ?? "goodvibrations HQ"
        }()

        let subtitle: String = {
            if isOpening {
                return "Opening in Live…"
            }
            if let ver = store.currentOpenProject?.newestAbletonVersion?.displayName {
                return "\(ver) • Ableton Live"
            }
            if isLiveActive {
                return "Active in Live"
            }
            return "goodvibrations HQ"
        }()

        return HStack(spacing: 8) {
            // Drag and click area covers indicator and text labels
            HStack(spacing: 8) {
                // Mini status indicator
                if isOpening {
                    ProgressView()
                        .controlSize(.mini)
                } else if isLiveActive {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1))
                        .shadow(color: Color.green.opacity(0.6), radius: 3)
                } else {
                    Circle()
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(projectName)
                        .font(.system(size: size.capsuleTitleFontSize, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: size.capsuleSubtitleFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .overlay(
                PetPuckDragArea {
                    expandWidget()
                }
            )

            // Open in Ableton Live Button
            Button {
                if let project = store.currentOpenProject ?? activeProject {
                    store.openInAbleton(project)
                } else {
                    _ = AbletonSessionDetector.activateAbleton()
                }
            } label: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: size.capsuleSubtitleFontSize, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: size.capsuleHeight * 0.58, height: size.capsuleHeight * 0.58)
                    .background(Color.primary.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Open in Ableton Live")
        }
        .padding(.horizontal, 10)
        .frame(width: size.capsuleWidth, height: size.capsuleHeight)
        .background(
            Capsule()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                .background(.ultraThinMaterial, in: Capsule())
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 6, x: 0, y: 2)
    }

    private var puckHelpText: String {
        if let project = store.currentOpenProject {
            return "Active in Ableton Live: \(project.name) (click to expand HUD, drag to move)"
        }
        if let opening = store.openingAbletonProject {
            return "Opening \(opening.projectName) in Live (click to expand HUD, drag to move)"
        }
        return "Click to expand goodvibrations HUD (drag to move)"
    }

    private func expandWidget() {
        settings.isFloatingWidgetCollapsed = false
        WindowPresenter.setFloatingWidgetCollapsed(false, pinned: true, puckSize: settings.petPuckSize.dimension)
    }

    private func collapseWidget() {
        settings.isFloatingWidgetCollapsed = true
        WindowPresenter.setFloatingWidgetCollapsed(
            true,
            pinned: true,
            puckSize: settings.petPuckSize.dimension,
            targetWidth: currentPuckWidth,
            targetHeight: currentPuckHeight
        )
    }

    // MARK: - Expanded HUD View

    private var expandedHudView: some View {
        VStack(spacing: 0) {
            headerBar
            if let opening = store.openingAbletonProject {
                openingBanner(opening)
            }
            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    if let hero = activeProject {
                        heroCard(project: hero)
                    }

                    controlsBar

                    projectList
                }
                .padding(10)
            }

            if audioPlayer.currentTrack != nil {
                Divider()
                nowPlayingBar
            }
        }
        .frame(minWidth: 280, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .background(
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                WindowDragArea()
            }
        )
        .animation(.easeInOut(duration: 0.2), value: store.openingAbletonProject)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func openingBanner(_ opening: AbletonOpeningState) -> some View {
        HStack(spacing: 8) {
            if opening.phase == .opening {
                ProgressView().controlSize(.mini)
                Text("Opening \(opening.projectName) in Live…")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.green)
                Text("\(opening.projectName) is ready in Live")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                store.dismissAbletonOpeningAlert()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(2)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Color.accentColor.opacity(opening.phase == .opening ? 0.12 : 0.08),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    opening.phase == .opening ? Color.accentColor.opacity(0.3) : Color.green.opacity(0.3),
                    lineWidth: 1
                )
        )
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 6) {
            if let icon = appIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 15, height: 15)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }

            Text("goodvibrations HUD")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.primary)

            if store.projects.count > 0 {
                Text("· \(store.projects.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Draggable Spacer across the entire header
            WindowDragArea()
                .frame(minWidth: 10, maxWidth: .infinity)
                .frame(height: 24)

            // Open in goodvibrations HQ Main Window
            Button {
                openWindow(id: "main-window")
                WindowPresenter.showMainWindow()
                if let p = activeProject {
                    store.openInMainWindow(p)
                }
            } label: {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Open in goodvibrations HQ")

            // Pin Button
            Button {
                settings.isFloatingWidgetPinned.toggle()
                WindowPresenter.configureFloatingWidget(
                    pinned: settings.isFloatingWidgetPinned,
                    collapsed: settings.isFloatingWidgetCollapsed
                )
            } label: {
                Image(systemName: settings.isFloatingWidgetPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .foregroundStyle(settings.isFloatingWidgetPinned ? Color.accentColor : .secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(settings.isFloatingWidgetPinned ? "Unpin from top" : "Keep on top")

            // Collapse to Floating Pet Icon
            Button {
                collapseWidget()
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Collapse to floating pet icon")

            // Close Button (collapses by default, option-click hides completely)
            Button {
                if NSEvent.modifierFlags.contains(.option) {
                    settings.isFloatingWidgetActive = false
                    WindowPresenter.hideFloatingWidget()
                } else {
                    collapseWidget()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.45))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Close to floating icon (Option-click to hide completely)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            ZStack {
                Color(nsColor: .controlBackgroundColor).opacity(0.6)
                WindowDragArea()
            }
        )
    }

    // MARK: - Hero Card (High Contrast)

    private func heroCard(project: Project) -> some View {
        let isLiveSession = store.isCurrentOpenProject(project)

        return VStack(alignment: .leading, spacing: 7) {
            // Header Pill Badge + Relative Date
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(isLiveSession ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(isLiveSession ? "LIVE SESSION" : "LAST ACTIVE")
                        .font(.system(size: 8.5, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(isLiveSession ? Color.green : Color.orange)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background((isLiveSession ? Color.green : Color.orange).opacity(0.14), in: Capsule())
                .overlay(Capsule().stroke((isLiveSession ? Color.green : Color.orange).opacity(0.35), lineWidth: 0.8))

                Spacer()

                if let saved = project.latestSavedItem?.date {
                    Text(formatRelative(saved))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            // Project Title & Musical Info
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.system(size: 13.5, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                HStack(spacing: 5) {
                    if let bpm = project.bpmLabel {
                        Text("\(bpm) BPM")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 3.5))
                            .overlay(RoundedRectangle(cornerRadius: 3.5).stroke(Color.primary.opacity(0.14), lineWidth: 0.5))
                    }
                    if let key = project.key {
                        Text(key)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 3.5))
                            .overlay(RoundedRectangle(cornerRadius: 3.5).stroke(Color.primary.opacity(0.14), lineWidth: 0.5))
                    }
                    if let track = project.sortedTracks.first?.displayName {
                        Text(track)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            // 1-Click Action Buttons Bar
            HStack(spacing: 6) {
                if project.newestAbletonVersion != nil {
                    Button {
                        store.openInAbleton(project)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.forward.app.fill")
                                .font(.system(size: 9.5))
                            Text("Open Live")
                                .font(.system(size: 10.5, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 5))
                        .foregroundColor(.white)
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                    .help("Launch or switch to this set in Ableton Live")
                }

                if let track = project.sortedTracks.first {
                    Button {
                        if audioPlayer.currentTrack?.id == track.id {
                            audioPlayer.togglePlayPause()
                        } else {
                            store.playTrack(track)
                        }
                    } label: {
                        Image(systemName: audioPlayer.currentTrack?.id == track.id && audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.15), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Audition demo audio")
                }

                Button {
                    NSWorkspace.shared.open(project.folderURL)
                } label: {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.15), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .help("Open in Finder")

                Button {
                    store.openInMainWindow(project)
                } label: {
                    Image(systemName: "macwindow")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.15), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .help("Open in goodvibrations HQ")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isLiveSession ? Color.green.opacity(0.45) : Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Filter & Search Controls

    private var controlsBar: some View {
        VStack(spacing: 6) {
            Picker("Filter", selection: $filter) {
                ForEach(FloatingWidgetFilter.allCases, id: \.self) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search songs…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4.5)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.12), lineWidth: 0.8))
        }
    }

    // MARK: - Projects List

    private var projectList: some View {
        VStack(spacing: 3) {
            if displayedProjects.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: filter == .favourites ? "star.slash" : "music.note")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                    Text(filter == .favourites ? "No favourite songs yet" : "No songs found")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(displayedProjects) { project in
                    projectRow(project: project)
                }
            }
        }
    }

    private func projectRow(project: Project) -> some View {
        let isCurrentSession = store.isCurrentOpenProject(project)
        let isFav = store.favourites.contains(project.folderURL)
        let isPlayingThis = project.tracks.contains { $0.id == audioPlayer.currentTrack?.id } && audioPlayer.isPlaying

        return HStack(spacing: 7) {
            // Star Button (High Contrast)
            Button {
                store.toggleFavourite(project)
            } label: {
                Image(systemName: isFav ? "star.fill" : "star")
                    .font(.system(size: 11, weight: isFav ? .bold : .medium))
                    .foregroundStyle(isFav ? Color(red: 1.0, green: 0.78, blue: 0.1) : Color.primary.opacity(0.35))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(isFav ? "Remove from favourites" : "Add to favourites")

            // Project Info
            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 4) {
                    if isCurrentSession {
                        Circle().fill(Color.green).frame(width: 5, height: 5)
                    }
                    Text(project.name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                if let saved = project.latestSavedItem?.date {
                    Text(formatRelative(saved))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // 1-Click Play / Audition Button
            if let track = project.sortedTracks.first {
                Button {
                    if audioPlayer.currentTrack?.id == track.id {
                        audioPlayer.togglePlayPause()
                    } else {
                        store.playTrack(track)
                    }
                } label: {
                    Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isPlayingThis ? Color.accentColor : Color.primary.opacity(0.75))
                        .frame(width: 20, height: 20)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 3.5))
                }
                .buttonStyle(.plain)
                .help("Play demo audio")
            }

            // 1-Click Open in Live DAW Button (Super High Contrast)
            if project.newestAbletonVersion != nil {
                Button {
                    store.openInAbleton(project)
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.up.forward.app.fill")
                            .font(.system(size: 7.5))
                        Text("DAW")
                            .font(.system(size: 8.5, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 4))
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .help("Open in Ableton Live")
            }

            // 1-Click Open in Finder Button
            Button {
                NSWorkspace.shared.open(project.folderURL)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Open in Finder")

            // 1-Click Open in goodvibrations HQ Button
            Button {
                openWindow(id: "main-window")
                WindowPresenter.showMainWindow()
                store.openInMainWindow(project)
            } label: {
                Image(systemName: "macwindow")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Open in goodvibrations HQ")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isCurrentSession ? Color.green.opacity(0.09) : Color(nsColor: .controlBackgroundColor).opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(isCurrentSession ? Color.green.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: 0.8)
        )
    }

    // MARK: - Now Playing Mini-Bar

    private var nowPlayingBar: some View {
        HStack(spacing: 8) {
            Button {
                audioPlayer.togglePlayPause()
            } label: {
                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22, height: 22)
                    .background(Color.accentColor.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)

            if let track = audioPlayer.currentTrack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.displayName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(formatDuration(audioPlayer.currentTime)) / \(formatDuration(audioPlayer.duration))")
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                store.playPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button {
                store.playNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Formatting Helpers

    private func formatRelative(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let mins = max(1, Int(interval / 60))
            return "\(mins)m ago"
        } else if interval < 86400 {
            let hours = max(1, Int(interval / 3600))
            return "\(hours)h ago"
        } else {
            let days = max(1, Int(interval / 86400))
            if days == 1 { return "Yesterday" }
            return "\(days)d ago"
        }
    }

    private func formatDuration(_ time: TimeInterval) -> String {
        guard time.isFinite && !time.isNaN else { return "0:00" }
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Window Drag Components

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragNSView {
        DragNSView()
    }

    func updateNSView(_ nsView: DragNSView, context: Context) {}
}

class DragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override var mouseDownCanMoveWindow: Bool {
        return true
    }
}

struct PetPuckDragArea: NSViewRepresentable {
    var onClick: () -> Void

    func makeNSView(context: Context) -> PetPuckDragNSView {
        let view = PetPuckDragNSView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: PetPuckDragNSView, context: Context) {
        nsView.onClick = onClick
    }
}

class PetPuckDragNSView: NSView {
    var onClick: (() -> Void)?
    private var initialMouseScreenLocation: NSPoint = .zero
    private var initialWindowOrigin: NSPoint = .zero
    private var hasMoved = false
    private let dragThreshold: CGFloat = 4.0

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window = self.window else { return }
        initialMouseScreenLocation = NSEvent.mouseLocation
        initialWindowOrigin = window.frame.origin
        hasMoved = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window else { return }
        let currentMouseScreenLocation = NSEvent.mouseLocation
        let dx = currentMouseScreenLocation.x - initialMouseScreenLocation.x
        let dy = currentMouseScreenLocation.y - initialMouseScreenLocation.y

        if !hasMoved {
            let distance = hypot(dx, dy)
            if distance >= dragThreshold {
                hasMoved = true
            }
        }

        if hasMoved {
            NSCursor.closedHand.set()
            window.setFrameOrigin(NSPoint(
                x: initialWindowOrigin.x + dx,
                y: initialWindowOrigin.y + dy
            ))
        }
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.openHand.set()
        if !hasMoved {
            onClick?()
        }
        hasMoved = false
    }

    override var mouseDownCanMoveWindow: Bool {
        return false
    }
}

