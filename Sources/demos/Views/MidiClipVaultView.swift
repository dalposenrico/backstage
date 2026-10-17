import SwiftUI
import AppKit

struct MidiClipVaultView: View {
    let arrangement: AbletonArrangement
    let projectName: String
    @StateObject private var midiPlayer = MidiClipPlayer.shared
    @State private var searchText = ""

    init(arrangement: AbletonArrangement, projectName: String) {
        self.arrangement = arrangement
        self.projectName = projectName
    }

    private var allClips: [AbletonClip] {
        arrangement.midiClips.sorted { $0.startTimeBeats < $1.startTimeBeats }
    }

    private var displayedClips: [AbletonClip] {
        if searchText.isEmpty { return allClips }
        return allClips.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "pianokeys")
                        .foregroundColor(.accent)
                        .font(.system(size: 11))
                    Text("\(allClips.count) MIDI clips · \(allClips.map(\.notes.count).reduce(0, +)) total notes")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primaryText)
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(.tertiaryText)
                    TextField("Search MIDI clips...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.sidebarBg, in: RoundedRectangle(cornerRadius: 6))
                .frame(width: 180)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.sidebarBg.opacity(0.7))

            Divider().background(Color.divider)

            if displayedClips.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "pianokeys")
                        .font(.system(size: 24))
                        .foregroundColor(.tertiaryText)
                    Text("No MIDI clips found")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(displayedClips) { clip in
                            clipRow(clip)
                            Divider().background(Color.white.opacity(0.04))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func clipRow(_ clip: AbletonClip) -> some View {
        let isPlaying = midiPlayer.isPlaying && midiPlayer.currentClipId == clip.id

        return HStack(spacing: 12) {
            // Audition play button
            Button {
                midiPlayer.toggle(clip: clip, tempo: arrangement.tempo)
            } label: {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill(isPlaying ? Color.accent : Color.white.opacity(0.14))
                    )
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Stop auditioning" : "Audition MIDI notes")

            // Color indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(clip.color)
                .frame(width: 4, height: 26)

            // Clip Name
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primaryText)

                HStack(spacing: 8) {
                    Text("Bar \(Int(clip.startTimeBeats / 4) + 1)")
                    Text("·")
                    Text("\(String(format: "%.1f", clip.durationBeats / 4)) bars")
                    Text("·")
                    Text("\(clip.notes.count) notes")
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.tertiaryText)
            }

            Spacer()

            if let range = clip.pitchRange {
                let minName = AbletonNote(pitch: range.lowerBound, startBeat: 0, durationBeats: 0).noteName
                let maxName = AbletonNote(pitch: range.upperBound, startBeat: 0, durationBeats: 0).noteName
                Text("\(minName) - \(maxName)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.elevatedBg, in: RoundedRectangle(cornerRadius: 4))
            }

            // Drag badge
            HStack(spacing: 4) {
                Image(systemName: "hand.draw")
                    .font(.system(size: 9))
                Text("Drag to Live")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.06), in: Capsule())
            .onDrag {
                exportClipForDrag(clip)
            }
        }
        .padding(.vertical, 6)
    }

    private func exportClipForDrag(_ clip: AbletonClip) -> NSItemProvider {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("HQClips", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let safeName = clip.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let url = tempDir.appendingPathComponent("\(safeName).mid")

        _ = try? StandardMidiWriter.writeMidi(
            notes: clip.notes,
            tempo: arrangement.tempo,
            trackName: clip.name,
            to: url
        )

        return NSItemProvider(contentsOf: url) ?? NSItemProvider()
    }
}
