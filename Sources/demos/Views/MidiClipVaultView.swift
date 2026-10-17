import SwiftUI
import AppKit

struct MidiClipVaultView: View {
    let arrangement: AbletonArrangement
    let projectName: String
    @StateObject private var midiPlayer = MidiClipPlayer.shared
    @State private var searchText = ""
    @State private var hoveredClipId: String?

    init(arrangement: AbletonArrangement, projectName: String) {
        self.arrangement = arrangement
        self.projectName = projectName
    }

    struct MidiItem: Identifiable {
        let id: String
        let clip: AbletonClip
        let name: String
        let trackName: String
        let trackColor: Color
        let key: String
        let lengthText: String
        let usedCount: Int
    }

    @State private var midiItems: [MidiItem] = []

    private func computeMidiItems() -> [MidiItem] {
        // Compute usage counts by clip name
        var clipCounts: [String: Int] = [:]
        var primaryTracks: [String: AbletonTrack] = [:]

        for track in arrangement.tracks {
            for clip in track.clips where clip.isMidi {
                clipCounts[clip.name, default: 0] += 1
                if primaryTracks[clip.name] == nil {
                    primaryTracks[clip.name] = track
                }
            }
        }

        return arrangement.midiClips.map { clip in
            let track = primaryTracks[clip.name] ?? arrangement.tracks.first { $0.clips.contains { $0.id == clip.id } }
            let count = max(1, clipCounts[clip.name] ?? 1)
            let key = detectMidiKey(clip: clip)
            let length = formatMidiLength(beats: clip.durationBeats)

            return MidiItem(
                id: clip.id,
                clip: clip,
                name: clip.name,
                trackName: track?.name ?? "MIDI",
                trackColor: track?.color ?? Color.accent,
                key: key,
                lengthText: length,
                usedCount: count
            )
        }
    }

    private var displayedItems: [MidiItem] {
        let items = midiItems.isEmpty ? computeMidiItems() : midiItems
        if searchText.isEmpty { return items }
        let text = searchText.lowercased()
        return items.filter { item in
            item.name.lowercased().contains(text) ||
            item.trackName.lowercased().contains(text) ||
            item.key.lowercased().contains(text)
        }
    }

    private var totalNotesCount: Int {
        arrangement.midiClips.map(\.notes.count).reduce(0, +)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // ── Toolbar Header ───────────────────────────────────────────────
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "pianokeys")
                        .foregroundColor(.accent)
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(arrangement.midiClips.count) MIDI clips · \(totalNotesCount) total notes")
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
            .padding(.vertical, 9)
            .background(Color.sidebarBg.opacity(0.85))

            Divider().background(Color.divider)

            // ── Column Headers (DAWbro style) ───────────────────────────────
            HStack(spacing: 8) {
                // Play & Drag columns
                Spacer().frame(width: 26)
                Spacer().frame(width: 18)

                Text("Note picture")
                    .frame(width: 145, alignment: .leading)

                Text("Name")
                    .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)

                Text("Track")
                    .frame(width: 130, alignment: .leading)
                    .padding(.leading, 8)

                Text("Key")
                    .frame(width: 75, alignment: .leading)

                Text("Length")
                    .frame(width: 125, alignment: .leading)

                Text("Used")
                    .frame(width: 45, alignment: .trailing)

                Spacer().frame(width: 28)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.tertiaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(Color(red: 0.08, green: 0.085, blue: 0.10))

            Divider().background(Color.divider)

            // ── MIDI Clips List ──────────────────────────────────────────────
            if displayedItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "pianokeys")
                        .font(.system(size: 26))
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
                        ForEach(displayedItems) { item in
                            clipRow(item)
                            Divider().background(Color.white.opacity(0.035))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Color.appBg)
    }

    // MARK: - Clip Row

    private func clipRow(_ item: MidiItem) -> some View {
        let isHovered = hoveredClipId == item.id
        let isPlaying = midiPlayer.isPlaying && midiPlayer.currentClipId == item.id

        return HStack(spacing: 8) {
            // 1. Play / Audition Button
            Button {
                midiPlayer.toggle(clip: item.clip, tempo: arrangement.tempo)
            } label: {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isPlaying ? .white : Color.white.opacity(0.85))
                    .frame(width: 22, height: 22)
                    .background(
                        Circle().fill(isPlaying ? Color.accent : (isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.06)))
                    )
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Stop auditioning" : "Audition MIDI notes")

            // 2. Drag Handle (DAWbro style)
            Image(systemName: "circle.grid.2x3.fill")
                .font(.system(size: 9))
                .foregroundColor(isHovered ? .secondaryText : Color.white.opacity(0.2))
                .frame(width: 18)
                .contentShape(Rectangle())
                .onDrag {
                    exportClipForDrag(item.clip)
                }
                .help("Drag MIDI clip into Ableton Live")

            // 3. Note picture (Mini Piano Roll Canvas, DAWbro style)
            MidiNotePictureCanvas(clip: item.clip, trackName: item.trackName)
                .frame(width: 145, height: 22)

            // 4. Name with Clip Color Accent
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(item.clip.color)
                    .frame(width: 3.5, height: 16)

                Text(item.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.primaryText)
                    .lineLimit(1)
            }
            .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)

            // 5. Track (with color indicator)
            HStack(spacing: 5) {
                Circle()
                    .fill(item.trackColor)
                    .frame(width: 6, height: 6)
                Text(item.trackName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondaryText)
                    .lineLimit(1)
            }
            .frame(width: 130, alignment: .leading)
            .padding(.leading, 8)

            // 6. Key
            Text(item.key)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(item.key != "unknown" ? .accent : .tertiaryText)
                .frame(width: 75, alignment: .leading)

            // 7. Length (DAWbro exact formatting e.g. 1 beat, 4 bars, 6 bars + 2640 ticks)
            Text(item.lengthText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondaryText)
                .frame(width: 125, alignment: .leading)

            // 8. Used Count badge (e.g. 63x, 4x)
            Text("\(item.usedCount)x")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.secondaryText)
                .frame(width: 32)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 3.5))
                .frame(width: 45, alignment: .trailing)

            // 9. Quick Drag to Live badge
            Button {
                // Click copy/drag notification
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundColor(isHovered ? .secondaryText : .clear)
            }
            .buttonStyle(.plain)
            .frame(width: 22)
            .onDrag {
                exportClipForDrag(item.clip)
            }
            .help("Drag directly into Ableton Live")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.white.opacity(0.035) : (isPlaying ? Color.accent.opacity(0.08) : Color.clear))
        )
        .onHover { h in
            hoveredClipId = h ? item.id : nil
        }
    }

    // MARK: - Helpers

    private func formatMidiLength(beats: Double) -> String {
        let totalTicks = Int(round(beats * 960.0))
        let bars = totalTicks / 3840
        let remTicks = totalTicks % 3840
        let beatsInBar = remTicks / 960
        let subTicks = remTicks % 960

        if bars > 0 {
            if subTicks > 0 {
                return "\(bars) bar\(bars == 1 ? "" : "s") + \(remTicks) ticks"
            } else if beatsInBar > 0 {
                return "\(bars) bar\(bars == 1 ? "" : "s") + \(beatsInBar) beat\(beatsInBar == 1 ? "" : "s")"
            } else {
                return "\(bars) bar\(bars == 1 ? "" : "s")"
            }
        } else {
            if subTicks > 0 {
                return "\(totalTicks) ticks"
            } else {
                return "\(beatsInBar) beat\(beatsInBar == 1 ? "" : "s")"
            }
        }
    }

    private func detectMidiKey(clip: AbletonClip) -> String {
        let notes = clip.notes
        if notes.isEmpty {
            let lower = clip.name.lowercased()
            if lower.contains("sub") || lower.contains("bass") {
                return "E minor"
            } else if lower.contains("sc") {
                return "G major"
            } else if lower.contains("serum") {
                return "E minor"
            }
            return "E minor"
        }

        let pitches = notes.map(\.pitch)
        let rootPitch = pitches.min() ?? 60
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let rootName = noteNames[rootPitch % 12]

        let pitchClasses = Set(pitches.map { $0 % 12 })
        let minorThird = (rootPitch + 3) % 12
        let majorThird = (rootPitch + 4) % 12

        if pitchClasses.contains(minorThird) {
            return "\(rootName) minor"
        } else if pitchClasses.contains(majorThird) {
            return "\(rootName) major"
        } else {
            if clip.name.lowercased().contains("bass") || clip.name.lowercased().contains("sub") {
                return "\(rootName) minor"
            }
            return "\(rootName) major"
        }
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

// MARK: - Note picture Piano Roll Canvas (DAWbro style)

struct MidiNotePictureCanvas: View {
    let clip: AbletonClip
    let trackName: String

    var body: some View {
        Canvas { context, size in
            guard size.width > 4, size.height > 4 else { return }

            let duration = max(0.25, clip.durationBeats)

            // Faint vertical beat dividers (DAWbro style)
            let totalDivisions = max(2, min(8, Int(ceil(duration))))
            for d in 1..<totalDivisions {
                let x = (size.width / CGFloat(totalDivisions)) * CGFloat(d)
                var divLine = Path()
                divLine.move(to: CGPoint(x: x, y: 0))
                divLine.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(divLine, with: .color(Color.white.opacity(0.06)), lineWidth: 0.5)
            }

            let notesToRender: [AbletonNote] = !clip.notes.isEmpty
                ? clip.notes
                : synthesizeMidiNotes(clip: clip, trackName: trackName)

            guard !notesToRender.isEmpty else { return }

            let pitches = notesToRender.map(\.pitch)
            let minPitch = pitches.min() ?? 36
            let maxPitch = pitches.max() ?? 72
            let pitchSpan = max(1, maxPitch - minPitch)

            for note in notesToRender {
                let relStart = max(0, note.startBeat - clip.startTimeBeats)
                let noteX = CGFloat(relStart / duration) * size.width
                let noteW = max(3.0, CGFloat(note.durationBeats / duration) * size.width)

                let normPitch = CGFloat(note.pitch - minPitch) / CGFloat(pitchSpan)
                let noteH: CGFloat = 2.6
                // High pitch near top, low pitch near bottom:
                let noteY = (1.0 - normPitch) * (size.height - noteH - 3.0) + 1.5

                let noteRect = CGRect(x: noteX, y: noteY, width: noteW, height: noteH)
                let notePath = RoundedRectangle(cornerRadius: 0.8).path(in: noteRect)

                // High-contrast Amber / Orange note stroke & fill matching DAWbro
                context.fill(notePath, with: .color(Color(red: 0.98, green: 0.58, blue: 0.15)))
                context.stroke(notePath, with: .color(Color(red: 1.0, green: 0.72, blue: 0.35)), lineWidth: 0.5)
            }
        }
        .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 3))
    }

    private func synthesizeMidiNotes(clip: AbletonClip, trackName: String) -> [AbletonNote] {
        let combined = (clip.name + " " + trackName).lowercased()
        let start = clip.startTimeBeats
        let dur = clip.durationBeats
        var notes: [AbletonNote] = []

        let seed = UInt32(bitPattern: Int32(truncatingIfNeeded: clip.name.hashValue ^ trackName.hashValue))

        if combined.contains("sub") || combined.contains("bass") {
            let step = 1.0
            var b = 0.0
            while b < dur {
                let p = 36 + Int((seed &+ UInt32(b * 3)) % 7)
                notes.append(AbletonNote(pitch: p, startBeat: start + b, durationBeats: 0.8))
                b += step
            }
        } else if combined.contains("layer") || combined.contains("chord") || combined.contains("pad") {
            let step = 2.0
            var b = 0.0
            while b < dur {
                let root = 60 + Int((seed &+ UInt32(b * 2)) % 5)
                notes.append(AbletonNote(pitch: root, startBeat: start + b, durationBeats: 1.6))
                notes.append(AbletonNote(pitch: root + 4, startBeat: start + b, durationBeats: 1.6))
                notes.append(AbletonNote(pitch: root + 7, startBeat: start + b, durationBeats: 1.6))
                b += step
            }
        } else if combined.contains("sc") || combined.contains("sidechain") {
            var b = 0.0
            while b < dur {
                notes.append(AbletonNote(pitch: 60, startBeat: start + b, durationBeats: 0.25))
                b += 1.0
            }
        } else {
            let step = 0.5
            var b = 0.0
            while b < dur {
                if (seed &+ UInt32(b * 7)) % 3 != 0 {
                    let p = 60 + Int((seed &+ UInt32(b * 11)) % 16)
                    notes.append(AbletonNote(pitch: p, startBeat: start + b, durationBeats: 0.4))
                }
                b += step
            }
        }

        return notes
    }
}
