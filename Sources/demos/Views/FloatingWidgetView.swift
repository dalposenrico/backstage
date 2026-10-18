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

    var body: some View {
        VStack(spacing: 0) {
            headerBar
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
        .background(.ultraThinMaterial)
        .background(Color.primary.opacity(0.03))
        .onAppear {
            WindowPresenter.configureFloatingWidget(pinned: settings.isFloatingWidgetPinned)
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.accentColor)

            Text("goodvibrations HUD")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.primary)

            if store.projects.count > 0 {
                Text("· \(store.projects.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Open in goodvibrations HQ Main Window
            Button {
                if let p = activeProject {
                    store.openInMainWindow(p)
                } else {
                    NSApp.activate(ignoringOtherApps: true)
                }
            } label: {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open in goodvibrations HQ")

            // Pin Button
            Button {
                settings.isFloatingWidgetPinned.toggle()
                WindowPresenter.configureFloatingWidget(pinned: settings.isFloatingWidgetPinned)
            } label: {
                Image(systemName: settings.isFloatingWidgetPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .foregroundStyle(settings.isFloatingWidgetPinned ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(settings.isFloatingWidgetPinned ? "Unpin from top" : "Keep on top")

            // Close Button
            Button {
                settings.isFloatingWidgetActive = false
                WindowPresenter.hideFloatingWidget()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Hide Floating Widget")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Hero Card

    private func heroCard(project: Project) -> some View {
        let isLiveSession = store.isCurrentOpenProject(project)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(isLiveSession ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(isLiveSession ? "LIVE SESSION" : "LAST ACTIVE")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(isLiveSession ? Color.green : Color.orange)

                Spacer()

                if let saved = project.latestSavedItem?.date {
                    Text(formatRelative(saved))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                HStack(spacing: 5) {
                    if let bpm = project.bpmLabel {
                        Text("\(bpm) BPM")
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                    }
                    if let key = project.key {
                        Text(key)
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                    }
                    if let track = project.sortedTracks.first?.displayName {
                        Text(track)
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            // 1-Click Action Buttons Bar
            HStack(spacing: 5) {
                if project.newestAbletonVersion != nil {
                    Button {
                        store.openInAbleton(project)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.forward.app.fill")
                                .font(.system(size: 9))
                            Text("Open Live")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 4))
                        .foregroundColor(.white)
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
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("Audition demo audio")
                }

                Button {
                    NSWorkspace.shared.open(project.folderURL)
                } label: {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Open in Finder")

                Button {
                    store.openInMainWindow(project)
                } label: {
                    Image(systemName: "macwindow")
                        .font(.system(size: 9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Open in goodvibrations HQ")
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isLiveSession ? Color.green.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Filter & Search Controls

    private var controlsBar: some View {
        VStack(spacing: 5) {
            Picker("Filter", selection: $filter) {
                ForEach(FloatingWidgetFilter.allCases, id: \.self) {
                    Text($0.rawValue).tag($0)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
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
            .padding(.horizontal, 6)
            .padding(.vertical, 3.5)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
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

        return HStack(spacing: 6) {
            // Star Button
            Button {
                store.toggleFavourite(project)
            } label: {
                Image(systemName: isFav ? "star.fill" : "star")
                    .font(.system(size: 10))
                    .foregroundStyle(isFav ? Color.yellow : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)

            // Project Info
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if isCurrentSession {
                        Circle().fill(Color.green).frame(width: 5, height: 5)
                    }
                    Text(project.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                if let saved = project.latestSavedItem?.date {
                    Text(formatRelative(saved))
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
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
                        .font(.system(size: 8.5))
                        .foregroundStyle(isPlayingThis ? Color.accentColor : Color.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Play demo audio")
            }

            // 1-Click Open in Live Button
            if project.newestAbletonVersion != nil {
                Button {
                    store.openInAbleton(project)
                } label: {
                    Text("DAW")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                }
                .buttonStyle(.plain)
                .help("Open in Ableton Live")
            }

            // 1-Click Open in Finder Button
            Button {
                NSWorkspace.shared.open(project.folderURL)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help("Open in Finder")

            // 1-Click Open in goodvibrations HQ Button
            Button {
                store.openInMainWindow(project)
            } label: {
                Image(systemName: "macwindow")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help("Open in goodvibrations HQ")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(isCurrentSession ? Color.green.opacity(0.06) : Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 4))
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
            }
            .buttonStyle(.plain)

            if let track = audioPlayer.currentTrack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    Text("\(formatDuration(audioPlayer.currentTime)) / \(formatDuration(audioPlayer.duration))")
                        .font(.system(size: 8.5, design: .monospaced))
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
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
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
