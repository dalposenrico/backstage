import SwiftUI
import AppKit

struct ArrangementTimelineView: View {
    let arrangement: AbletonArrangement
    let projectName: String
    @StateObject private var midiPlayer = MidiClipPlayer.shared
    @State private var selectedClip: AbletonClip?
    @State private var zoomLevel: Double = 1.0 // 0.5 to 3.0
    @State private var hoveredClipId: String?

    private let trackHeaderWidth: CGFloat = 160
    private let trackHeight: CGFloat = 36
    private let barHeaderHeight: CGFloat = 28
    private let beatsPerBar: Double = 4.0

    private var pixelsPerBeat: CGFloat {
        CGFloat(18.0 * zoomLevel)
    }

    private var totalTimelineWidth: CGFloat {
        max(600, CGFloat(arrangement.totalLengthBeats) * pixelsPerBeat)
    }

    init(arrangement: AbletonArrangement, projectName: String) {
        self.arrangement = arrangement
        self.projectName = projectName
        _selectedClip = State(initialValue: arrangement.midiClips.first ?? arrangement.tracks.first?.clips.first)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text("\(Int(arrangement.tempo)) BPM")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.accent)
                    Text("·")
                        .foregroundColor(.tertiaryText)
                    Text("\(arrangement.timeSignatureNumerator)/\(arrangement.timeSignatureDenominator)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondaryText)
                    Text("·")
                        .foregroundColor(.tertiaryText)
                    Text("\(arrangement.tracks.count) tracks, \(arrangement.sampleRefs.count) samples")
                        .font(.system(size: 11))
                        .foregroundColor(.tertiaryText)
                }

                Spacer()

                // Zoom controls
                HStack(spacing: 4) {
                    Button {
                        zoomLevel = max(0.5, zoomLevel - 0.25)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Zoom out timeline")

                    Button("Fit") {
                        zoomLevel = 1.0
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.elevatedBg, in: RoundedRectangle(cornerRadius: 4))

                    Button {
                        zoomLevel = min(3.0, zoomLevel + 0.25)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Zoom in timeline")
                }
                .foregroundColor(.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.sidebarBg.opacity(0.8))

            Divider().background(Color.divider)

            // Timeline area
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    // Ruler bar
                    timelineRuler
                        .frame(width: trackHeaderWidth + totalTimelineWidth, height: barHeaderHeight)
                        .background(Color.sidebarBg.opacity(0.95))

                    Divider().background(Color.divider)

                    // Track swimlanes
                    ForEach(arrangement.tracks) { track in
                        trackRow(track)
                            .frame(height: trackHeight)
                        Divider().background(Color.white.opacity(0.04))
                    }
                }
            }
            .background(Color.appBg)

            // Footer with selected clip inspection & Drag to DAW
            if let clip = selectedClip {
                Divider().background(Color.divider)
                clipDetailFooter(clip)
            }
        }
    }

    // MARK: - Ruler View

    private var timelineRuler: some View {
        HStack(spacing: 0) {
            Text("TRACKS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.tertiaryText)
                .frame(width: trackHeaderWidth, alignment: .leading)
                .padding(.leading, 14)

            ZStack(alignment: .leading) {
                let totalBars = Int(ceil(arrangement.totalLengthBeats / beatsPerBar))
                let step = zoomLevel >= 1.5 ? 1 : 4
                ForEach(Array(stride(from: 0, to: totalBars, by: step)), id: \.self) { bar in
                    let barNumber = bar + 1
                    let xPos = CGFloat(Double(bar) * beatsPerBar) * pixelsPerBeat
                    let totalSeconds = (Double(bar * 4) / arrangement.tempo) * 60.0
                    let minutes = Int(totalSeconds) / 60
                    let seconds = Int(totalSeconds) % 60
                    HStack(spacing: 3) {
                        Text("\(barNumber)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.primaryText)
                        Text(String(format: "%d:%02d", minutes, seconds))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.tertiaryText)
                    }
                    .offset(x: xPos + 2)
                }
            }
            .frame(width: totalTimelineWidth, height: barHeaderHeight, alignment: .leading)
        }
    }

    // MARK: - Track Row

    private func trackRow(_ track: AbletonTrack) -> some View {
        HStack(spacing: 0) {
            // Track Header
            HStack(spacing: 6) {
                Image(systemName: track.type.systemIcon)
                    .font(.system(size: 9))
                    .foregroundColor(track.color)
                    .frame(width: 14)

                Text(track.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .frame(width: trackHeaderWidth, height: trackHeight, alignment: .leading)
            .background(Color.sidebarBg.opacity(0.4))
            .border(Color.white.opacity(0.04), width: 0.5)

            // Timeline Track Area
            ZStack(alignment: .leading) {
                // Background grid lines (hardware-accelerated Canvas)
                Canvas { context, size in
                    let totalBars = Int(ceil(arrangement.totalLengthBeats / beatsPerBar))
                    var path = Path()
                    for bar in stride(from: 0, to: totalBars, by: 4) {
                        let x = CGFloat(Double(bar) * beatsPerBar) * pixelsPerBeat
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    context.stroke(path, with: .color(Color.white.opacity(0.03)), lineWidth: 1)
                }

                // Clips
                ForEach(track.clips) { clip in
                    clipView(clip, track: track)
                }
            }
            .frame(width: totalTimelineWidth, height: trackHeight, alignment: .leading)
        }
    }

    // MARK: - Clip View

    private func clipView(_ clip: AbletonClip, track: AbletonTrack) -> some View {
        let x = CGFloat(clip.startTimeBeats) * pixelsPerBeat
        let width = max(18.0, CGFloat(clip.durationBeats) * pixelsPerBeat)
        let isSelected = selectedClip?.id == clip.id
        let isPlaying = midiPlayer.isPlaying && midiPlayer.currentClipId == clip.id

        return ZStack(alignment: .topLeading) {
            // Clip background
            RoundedRectangle(cornerRadius: 3)
                .fill(clip.color.opacity(isSelected ? 0.9 : 0.72))
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(
                            isPlaying ? Color.white : (isSelected ? Color.white.opacity(0.85) : Color.black.opacity(0.2)),
                            lineWidth: isSelected || isPlaying ? 1.5 : 0.5
                        )
                }

            // Clip contents: Mini piano roll notes or audio waveform representation
            if clip.isMidi && !clip.notes.isEmpty {
                miniPianoRoll(clip: clip, width: width, height: trackHeight - 4)
            }

            // Clip Name
            Text(clip.name)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color.black.opacity(0.85))
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
        }
        .frame(width: width, height: trackHeight - 6)
        .offset(x: x, y: 3)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedClip = clip
        }
        .onDrag {
            exportClipForDrag(clip)
        }
        .help("Click to inspect, drag to drop into Ableton Live")
    }

    // MARK: - Mini Piano Roll

    private func miniPianoRoll(clip: AbletonClip, width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            guard let range = clip.pitchRange else { return }
            let minPitch = range.lowerBound
            let pitchSpan = max(1, range.upperBound - minPitch)
            let duration = max(0.25, clip.durationBeats)

            for note in clip.notes {
                let noteX = CGFloat((note.startBeat - clip.startTimeBeats) / duration) * size.width
                let noteWidth = max(2.0, CGFloat(note.durationBeats / duration) * size.width)
                let normPitch = CGFloat(note.pitch - minPitch) / CGFloat(pitchSpan)
                let noteY = (1.0 - normPitch) * (size.height - 8) + 4

                let noteRect = CGRect(x: noteX, y: noteY, width: noteWidth, height: 1.5)
                context.fill(Path(noteRect), with: .color(Color.black.opacity(0.75)))
            }
        }
        .frame(width: width, height: height)
        .padding(.top, 4)
    }

    // MARK: - Footer & Drag-to-DAW

    private func clipDetailFooter(_ clip: AbletonClip) -> some View {
        HStack(spacing: 16) {
            // Clip Identity
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(clip.color)
                    .frame(width: 10, height: 10)
                Text(clip.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primaryText)
            }

            Text("Bar \(Int(clip.startTimeBeats / 4) + 1) · \(String(format: "%.1f", clip.durationBeats / 4)) bars")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondaryText)

            if clip.isMidi {
                Text("\(clip.notes.count) notes")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondaryText)

                if let range = clip.pitchRange {
                    let minName = AbletonNote(pitch: range.lowerBound, startBeat: 0, durationBeats: 0).noteName
                    let maxName = AbletonNote(pitch: range.upperBound, startBeat: 0, durationBeats: 0).noteName
                    Text("\(minName) - \(maxName)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.tertiaryText)
                }

                // Play / Audition Button
                Button {
                    midiPlayer.toggle(clip: clip, tempo: arrangement.tempo)
                } label: {
                    Label(
                        midiPlayer.isPlaying && midiPlayer.currentClipId == clip.id ? "Stop Audition" : "Audition Clip",
                        systemImage: midiPlayer.isPlaying && midiPlayer.currentClipId == clip.id ? "stop.fill" : "play.fill"
                    )
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accent, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)

                // Drag to DAW button badge
                HStack(spacing: 4) {
                    Image(systemName: "hand.draw.fill")
                        .font(.system(size: 9))
                    Text("Drag clip directly into Ableton")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06), in: Capsule())
                .onDrag {
                    exportClipForDrag(clip)
                }
            } else if let sample = clip.sampleRef {
                HStack(spacing: 4) {
                    Image(systemName: sample.isMissing ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundColor(sample.isMissing ? .orange : .green)
                        .font(.system(size: 10))
                    Text(sample.fileName)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondaryText)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.sidebarBg.opacity(0.9))
    }

    // MARK: - Drag Export Helper

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
