import SwiftUI
import AppKit

// MARK: - Track list (right panel)

struct TrackListView: View {
    let project: Project
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var player: AudioPlayer

    var body: some View {
        VStack(spacing: 0) {

            // ── Project header ───────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {

                        // Name + Finder button
                        HStack(spacing: 10) {
                            Text(project.name)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(.primaryText)

                            Button { NSWorkspace.shared.open(project.folderURL) } label: {
                                Image(systemName: "arrow.up.forward.square")
                                    .font(.system(size: 15))
                                    .foregroundColor(.secondaryText)
                            }
                            .buttonStyle(.plain)
                            .help("Open in Finder")
                        }

                        // Finder color tags
                        if !project.tags.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(project.tags, id: \.self) { tag in
                                    if let color = Color.finderTagColor(tag) {
                                        HStack(spacing: 4) {
                                            Circle().fill(color).frame(width: 8, height: 8)
                                            Text(tag)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(color.opacity(0.9))
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(color.opacity(0.12))
                                        .cornerRadius(10)
                                    } else {
                                        Text(tag)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.secondaryText)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.white.opacity(0.06))
                                            .cornerRadius(10)
                                    }
                                }
                            }
                        }

                        // Metadata row — larger, higher contrast
                        HStack(spacing: 8) {
                            Text(project.hasExports
                                 ? "\(project.tracks.count) \(project.tracks.count == 1 ? "export" : "exports")"
                                 : "No exports yet")
                                .font(.system(size: 13))
                                .foregroundColor(project.hasExports ? .secondaryText : .tertiaryText)

                            if let created = project.creationDate {
                                Text("·").foregroundColor(.tertiaryText).font(.system(size: 13))
                                Text("Added \(created.fullDateTime)")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondaryText)
                            }

                            if project.latestModification != .distantPast {
                                Text("·").foregroundColor(.tertiaryText).font(.system(size: 13))
                                Text("Edited \(project.latestModification.relativeFull)")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondaryText)
                            }
                        }
                    }

                    Spacer()

                    // Play All (only shown when there are exports)
                    if project.hasExports {
                        Button {
                            if let first = project.sortedTracks.first { store.playTrack(first) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill").font(.system(size: 11))
                                Text("Play All").font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.accent)
                            .cornerRadius(20)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 18)

            Divider().background(Color.divider)

            // ── Content ──────────────────────────────────────────────────────
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {

                    // ── Exports section ──────────────────────────────────────
                    if !project.tracks.isEmpty {
                        ListSectionHeader(title: "Exports", count: project.tracks.count)

                        ForEach(project.sortedTracks) { track in
                            TrackRow(track: track)
                                .onTapGesture {
                                    player.currentTrack?.id == track.id
                                        ? player.togglePlayPause()
                                        : store.playTrack(track)
                                }
                        }
                    } else {
                        // No-export placeholder
                        HStack(spacing: 10) {
                            Image(systemName: "square.dashed")
                                .font(.system(size: 13))
                                .foregroundColor(.tertiaryText)
                            Text("No audio exports found in this project folder")
                                .font(.system(size: 13))
                                .foregroundColor(.tertiaryText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 20)
                    }

                    // ── Project versions (.als files) ────────────────────────
                    if !project.versions.isEmpty {
                        ListSectionHeader(title: "Project Files", count: project.versions.count)
                            .padding(.top, project.tracks.isEmpty ? 4 : 0)

                        ForEach(project.versions) { version in
                            AbletonVersionRow(version: version)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .overlay(alignment: .bottomTrailing) {
                ExpandWindowButton()
                    .padding(10)
            }
        }
        .background(Color.appBg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Section header

struct ListSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.tertiaryText)
                .tracking(0.8)
            Text("\(count)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.tertiaryText.opacity(0.6))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }
}

// MARK: - Audio track row

struct TrackRow: View {
    let track: Track
    @State private var isHovered = false
    @EnvironmentObject var player: AudioPlayer

    var isCurrent: Bool { player.currentTrack?.id == track.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            HStack(spacing: 14) {
                // State icon
                ZStack {
                    if isCurrent {
                        Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.accent)
                            .symbolEffect(.variableColor.iterative.dimInactiveLayers,
                                          isActive: player.isPlaying)
                    } else {
                        Image(systemName: isHovered ? "play.fill" : "music.note")
                            .font(.system(size: isHovered ? 11 : 10))
                            .foregroundColor(isHovered ? .primaryText : .secondaryText)
                    }
                }
                .frame(width: 18, alignment: .center)

                Text(track.displayName)
                    .font(.system(size: 14, weight: isCurrent ? .semibold : .regular))
                    .foregroundColor(isCurrent ? .accent : .primaryText)
                    .lineLimit(1)

                // Format badge
                Text(track.fileExtension)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondaryText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.07))
                    .cornerRadius(4)

                Spacer()

                if isCurrent {
                    Text("\(player.currentTime.mmss) / \(player.duration.mmss)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondaryText)
                        .animation(.none, value: player.currentTime)
                } else if let date = track.modificationDate {
                    Text(date.relativeFull)
                        .font(.system(size: 12))        // was 11
                        .foregroundColor(.secondaryText) // was tertiaryText
                        .lineLimit(1)
                }
            }

            // Creation date sub-line
            if !isCurrent, let created = track.creationDate {
                HStack(spacing: 4) {
                    Spacer().frame(width: 32)
                    Text("Added")
                        .foregroundColor(.tertiaryText)
                    Text(created.fullDateTime)
                        .foregroundColor(.secondaryText)  // was tertiaryText
                }
                .font(.system(size: 11))   // was 10
                .padding(.top, 3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(isCurrent
                      ? Color.accent.opacity(0.07)
                      : (isHovered ? Color.hoverBg : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - Ableton version row (.als file)

struct AbletonVersionRow: View {
    let version: AbletonVersion
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                // Document icon — visually distinct from the music note
                Image(systemName: "doc.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.secondaryText.opacity(0.6))
                    .frame(width: 18, alignment: .center)

                Text(version.displayName)
                    .font(.system(size: 14))
                    .foregroundColor(.secondaryText)
                    .lineLimit(1)

                // .als badge
                Text("als")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.accent.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accent.opacity(0.10))
                    .cornerRadius(4)

                Spacer()

                if let date = version.modificationDate {
                    Text(date.relativeFull)
                        .font(.system(size: 12))
                        .foregroundColor(.secondaryText)
                        .lineLimit(1)
                }
            }

            if let created = version.creationDate {
                HStack(spacing: 4) {
                    Spacer().frame(width: 32)
                    Text("Added")
                        .foregroundColor(.tertiaryText)
                    Text(created.fullDateTime)
                        .foregroundColor(.secondaryText)
                }
                .font(.system(size: 11))
                .padding(.top, 3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(isHovered ? Color.hoverBg : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - Expand window button

struct ExpandWindowButton: View {
    @State private var isExpanded   = false
    @State private var previousFrame: NSRect = .zero
    @State private var isHovered    = false

    func toggle() {
        guard let screen = NSScreen.main,
              let window = NSApp.keyWindow else { return }

        if isExpanded {
            window.setFrame(previousFrame, display: true, animate: true)
            isExpanded = false
        } else {
            previousFrame = window.frame
            let sf = screen.visibleFrame
            let w  = sf.width  * 0.65
            let h  = sf.height * 0.72
            let x  = sf.minX + (sf.width  - w) / 2
            let y  = sf.minY + (sf.height - h) / 2
            window.setFrame(NSRect(x: x, y: y, width: w, height: h),
                            display: true, animate: true)
            isExpanded = true
        }
    }

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isExpanded
                  ? "arrow.down.right.and.arrow.up.left"
                  : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11))
                .foregroundColor(isHovered ? .secondaryText : .tertiaryText)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isHovered ? Color.hoverBg : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(isExpanded ? "Restore size" : "Expand window to 65%")
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}
