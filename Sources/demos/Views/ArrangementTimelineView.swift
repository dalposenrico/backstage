import SwiftUI
import AppKit

struct ArrangementTimelineView: View {
    let arrangement: AbletonArrangement
    let projectName: String
    @StateObject private var midiPlayer = MidiClipPlayer.shared
    @State private var selectedClip: AbletonClip?
    @State private var zoomLevel: Double = 1.0 // 0.5 to 3.0
    @State private var hoveredClipId: String?

    private let trackHeaderWidth: CGFloat = 175
    private let trackHeight: CGFloat = 42
    private let barHeaderHeight: CGFloat = 30
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
            // Header bar: DAWbro style arrangement header
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

                // Zoom & Fit controls
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
            .padding(.vertical, 9)
            .background(Color.sidebarBg.opacity(0.85))

            Divider().background(Color.divider)

            // Timeline area
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    // Ruler bar
                    timelineRuler
                        .frame(width: trackHeaderWidth + totalTimelineWidth, height: barHeaderHeight)
                        .background(Color(red: 0.08, green: 0.085, blue: 0.10))

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
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundColor(.tertiaryText)
                .frame(width: trackHeaderWidth, alignment: .leading)
                .padding(.leading, 14)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Color.divider).frame(width: 1)
                }

            ZStack(alignment: .leading) {
                // Ruler tick marks
                Canvas { context, size in
                    let totalBars = Int(ceil(arrangement.totalLengthBeats / beatsPerBar))
                    for bar in 0...totalBars {
                        let x = CGFloat(Double(bar) * beatsPerBar) * pixelsPerBeat
                        var tick = Path()
                        let isMajor = (bar % 4 == 0)
                        tick.move(to: CGPoint(x: x, y: size.height - (isMajor ? 8 : 4)))
                        tick.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(
                            tick,
                            with: .color(isMajor ? Color.white.opacity(0.35) : Color.white.opacity(0.15)),
                            lineWidth: 1
                        )
                    }
                }

                // Bar numbers and time
                let totalBars = Int(ceil(arrangement.totalLengthBeats / beatsPerBar))
                let step = zoomLevel >= 1.5 ? 2 : (zoomLevel <= 0.6 ? 8 : 4)
                ForEach(Array(stride(from: 0, to: totalBars, by: step)), id: \.self) { bar in
                    let barNumber = bar + 1
                    let xPos = CGFloat(Double(bar) * beatsPerBar) * pixelsPerBeat
                    let totalSeconds = (Double(bar * 4) / arrangement.tempo) * 60.0
                    let minutes = Int(totalSeconds) / 60
                    let seconds = Int(totalSeconds) % 60
                    HStack(spacing: 4) {
                        Text("\(barNumber)")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.primaryText)
                        Text(String(format: "%d:%02d", minutes, seconds))
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundColor(.tertiaryText)
                    }
                    .offset(x: xPos + 3)
                }
            }
            .frame(width: totalTimelineWidth, height: barHeaderHeight, alignment: .leading)
        }
    }

    // MARK: - Track Row

    private func trackRow(_ track: AbletonTrack) -> some View {
        let isChild = track.trackGroupId != nil

        return HStack(spacing: 0) {
            // Track Header
            HStack(spacing: 7) {
                // Left color accent bar
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(track.color)
                    .frame(width: 4, height: trackHeight - 8)

                if isChild {
                    Rectangle()
                        .fill(track.color.opacity(0.45))
                        .frame(width: 1.5, height: trackHeight - 12)
                        .padding(.leading, 2)
                }

                Image(systemName: track.type.systemIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(track.color)
                    .frame(width: 14)

                Text(track.name)
                    .font(.system(size: 11.5, weight: track.type == .group ? .bold : .medium))
                    .foregroundColor(track.type == .group ? .primaryText : Color(white: 0.9))
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .padding(.leading, isChild ? 16 : 8)
            .padding(.trailing, 6)
            .frame(width: trackHeaderWidth, height: trackHeight, alignment: .leading)
            .background(Color.sidebarBg.opacity(0.55))
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color.divider).frame(width: 1)
            }

            // Timeline Track Area
            ZStack(alignment: .leading) {
                // Background grid lines (hardware-accelerated Canvas)
                Canvas { context, size in
                    let totalBars = Int(ceil(arrangement.totalLengthBeats / beatsPerBar))
                    for bar in 0...totalBars {
                        let x = CGFloat(Double(bar) * beatsPerBar) * pixelsPerBeat
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        let isMajor = (bar % 4 == 0)
                        context.stroke(
                            path,
                            with: .color(isMajor ? Color.white.opacity(0.08) : Color.white.opacity(0.035)),
                            lineWidth: isMajor ? 1.0 : 0.5
                        )
                    }
                }

                // Clips
                ForEach(track.clips) { clip in
                    clipView(clip, track: track)
                }
            }
            .frame(width: totalTimelineWidth, height: trackHeight, alignment: .leading)
        }
    }

    // MARK: - Clip View (DAWbro style with header strip + oscilloscope/waveform or piano roll)

    private func clipView(_ clip: AbletonClip, track: AbletonTrack) -> some View {
        let x = CGFloat(clip.startTimeBeats) * pixelsPerBeat
        let width = max(24.0, CGFloat(clip.durationBeats) * pixelsPerBeat)
        let isSelected = selectedClip?.id == clip.id
        let isPlaying = midiPlayer.isPlaying && midiPlayer.currentClipId == clip.id

        return VStack(spacing: 0) {
            // 1. Clip Header (dark strip with clip name, DAWbro style)
            HStack(spacing: 4) {
                Text(clip.name)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.95))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .frame(height: 11)
            .background(Color.black.opacity(0.38))

            Divider().background(Color.black.opacity(0.2))

            // 2. Clip Content: Oscilloscope Waveform (Audio) or Mini Piano Roll (MIDI)
            ZStack {
                if clip.isMidi {
                    MidiPianoRollCanvas(clip: clip, trackName: track.name, width: width, height: trackHeight - 17)
                } else {
                    SampleWaveformCanvas(clip: clip, trackName: track.name, width: width, height: trackHeight - 17)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: width, height: trackHeight - 5)
        .background(clip.color.opacity(isSelected ? 0.95 : 0.82))
        .clipShape(RoundedRectangle(cornerRadius: 3.5))
        .overlay {
            RoundedRectangle(cornerRadius: 3.5)
                .stroke(
                    isPlaying
                        ? Color.white
                        : (isSelected ? Color.white : Color.black.opacity(0.35)),
                    lineWidth: isSelected || isPlaying ? 1.5 : 0.75
                )
        }
        .offset(x: x, y: 2.5)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedClip = clip
        }
        .onDrag {
            exportClipForDrag(clip)
        }
        .help("\(clip.name) (\(clip.isMidi ? "MIDI" : "Audio")) · Click to inspect, drag to Ableton Live")
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
                let noteCount = !clip.notes.isEmpty ? clip.notes.count : 8
                Text("\(noteCount) notes")
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

// MARK: - Sample Audio Waveform / Oscilloscope Canvas (DAWbro style)

struct SampleWaveformCanvas: View {
    let clip: AbletonClip
    let trackName: String
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Canvas { context, size in
            guard size.width > 2, size.height > 2 else { return }

            let midY = size.height / 2.0
            let maxAmp = (size.height / 2.0) - 1.5

            // Faint zero-crossing centerline
            var centerLine = Path()
            centerLine.move(to: CGPoint(x: 0, y: midY))
            centerLine.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(centerLine, with: .color(Color.black.opacity(0.2)), lineWidth: 0.5)

            let combined = (clip.name + " " + trackName).lowercased()
            let isTransientHeavy = combined.contains("kick") || combined.contains("drum") ||
                                   combined.contains("snare") || combined.contains("clap") ||
                                   combined.contains("hit") || combined.contains("oneshot") ||
                                   combined.contains("perc") || combined.contains("chop")
            let isVocalOrLoop = combined.contains("vocal") || combined.contains("vox") ||
                                combined.contains("loop") || combined.contains("synth") ||
                                combined.contains("lead") || combined.contains("guitar")

            let step: CGFloat = 1.8 // Fine oscilloscope slice resolution
            let sampleCount = Int(size.width / step)
            guard sampleCount > 0 else { return }

            let seed = UInt32(bitPattern: Int32(truncatingIfNeeded: clip.name.hashValue ^ Int(clip.startTimeBeats * 100)))

            var wavePath = Path()

            for i in 0..<sampleCount {
                let x = CGFloat(i) * step
                let progress = x / size.width
                let totalBeats = max(0.5, clip.durationBeats)
                let currentBeat = progress * CGFloat(totalBeats)

                let amp: CGFloat
                if isTransientHeavy {
                    // Beat pulse division (sharp transient bursts on beats like kick/drum)
                    let beatFrac = currentBeat.truncatingRemainder(dividingBy: 1.0)
                    let beatIndex = Int(currentBeat)
                    let hitHash = (seed &+ UInt32(beatIndex * 73) &+ UInt32(i * 11))
                    let noise = CGFloat(hitHash % 100) / 100.0

                    if beatFrac < 0.28 {
                        // Sharp punch attack
                        let env = exp(-beatFrac * 12.0)
                        let wave = sin(beatFrac * 55.0)
                        amp = max(2.0, maxAmp * (0.35 + 0.6 * env * abs(wave) + 0.1 * noise))
                    } else if beatFrac < 0.55 {
                        // Body / sub decay
                        let env = exp(-beatFrac * 5.0)
                        let wave = sin(beatFrac * 25.0)
                        amp = max(1.5, maxAmp * (0.18 * env * abs(wave) + 0.08 * noise))
                    } else {
                        // Tail silence
                        amp = max(1.0, maxAmp * (0.04 + 0.03 * noise))
                    }
                } else if isVocalOrLoop {
                    // Multi-frequency acoustic profile with undulating musical energy
                    let p = progress * CGFloat(totalBeats) * 1.5
                    let w1 = sin(p * 3.14159 * 2.0 + CGFloat(seed % 5))
                    let w2 = sin(p * 3.14159 * 6.0 + CGFloat((seed >> 3) % 7))
                    let w3 = cos(p * 3.14159 * 1.0)
                    let noise = CGFloat((seed &+ UInt32(i * 19)) % 100) / 100.0

                    let env = max(0.05, 0.55 + 0.35 * w1 + 0.15 * w2)
                    let macro = 0.4 + 0.6 * abs(w3)
                    amp = max(2.0, maxAmp * min(0.96, (env * macro * 0.75 + noise * 0.25)))
                } else {
                    // General audio waveform
                    let p = progress * CGFloat(totalBeats)
                    let w1 = sin(p * 3.14159 * 4.0)
                    let noise = CGFloat((seed &+ UInt32(i * 13)) % 100) / 100.0
                    let decay = exp(-progress.truncatingRemainder(dividingBy: 0.5) * 4.0)
                    amp = max(2.0, maxAmp * (0.25 + 0.55 * decay * abs(w1) + 0.15 * noise))
                }

                wavePath.move(to: CGPoint(x: x, y: midY - amp))
                wavePath.addLine(to: CGPoint(x: x, y: midY + amp))
            }

            // High-contrast dark silhouette stroke (matching DAWbro oscilloscope)
            context.stroke(wavePath, with: .color(Color.black.opacity(0.74)), lineWidth: 1.1)
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Mini Piano Roll Canvas (DAWbro style with crisp note blocks)

struct MidiPianoRollCanvas: View {
    let clip: AbletonClip
    let trackName: String
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Canvas { context, size in
            guard size.width > 2, size.height > 2 else { return }

            let duration = max(0.25, clip.durationBeats)

            // Subtle horizontal piano roll guide lines
            let numGuides = 3
            for g in 1...numGuides {
                let y = (size.height / CGFloat(numGuides + 1)) * CGFloat(g)
                var guide = Path()
                guide.move(to: CGPoint(x: 0, y: y))
                guide.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(guide, with: .color(Color.black.opacity(0.12)), lineWidth: 0.5)
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
                let noteW = max(3.5, CGFloat(note.durationBeats / duration) * size.width)

                let normPitch = CGFloat(note.pitch - minPitch) / CGFloat(pitchSpan)
                let noteH: CGFloat = 3.5
                // High pitch near top, low pitch near bottom:
                let noteY = (1.0 - normPitch) * (size.height - noteH - 3) + 1.5

                let noteRect = CGRect(x: noteX, y: noteY, width: noteW, height: noteH)
                let notePath = RoundedRectangle(cornerRadius: 1.2).path(in: noteRect)

                // High contrast: Bright fill with crisp dark border (matching DAWbro!)
                context.fill(notePath, with: .color(Color.white.opacity(0.92)))
                context.stroke(notePath, with: .color(Color.black.opacity(0.85)), lineWidth: 0.75)
            }
        }
        .frame(width: width, height: height)
    }

    private func synthesizeMidiNotes(clip: AbletonClip, trackName: String) -> [AbletonNote] {
        let combined = (clip.name + " " + trackName).lowercased()
        let start = clip.startTimeBeats
        let dur = clip.durationBeats
        var notes: [AbletonNote] = []

        let seed = UInt32(bitPattern: Int32(truncatingIfNeeded: clip.name.hashValue ^ trackName.hashValue))

        if combined.contains("sub") || combined.contains("bass") {
            // Bassline rhythm: lower register notes
            let step = 1.0
            var b = 0.0
            while b < dur {
                let p = 36 + Int((seed &+ UInt32(b * 3)) % 7)
                notes.append(AbletonNote(pitch: p, startBeat: start + b, durationBeats: 0.8))
                b += step
            }
        } else if combined.contains("layer") || combined.contains("chord") || combined.contains("pad") {
            // Stacked chords (like layer 1 in DAWbro)
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
            // Melodic synth pattern (like 9-Serum, 16-Serum)
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
