import SwiftUI
import AppKit
import AVFoundation

struct SampleHealthAuditorView: View {
    let arrangement: AbletonArrangement
    let project: Project
    @StateObject private var samplePlayer = SampleAudioPlayer.shared
    @State private var filterMissingOnly = false
    @State private var searchText = ""
    @State private var hoveredSampleId: String?

    init(arrangement: AbletonArrangement, project: Project) {
        self.arrangement = arrangement
        self.project = project
    }

    struct SampleItem: Identifiable {
        let id: String
        let sample: AbletonSampleRef
        let fileName: String
        let fileURL: URL?
        let isMissing: Bool
        let usedCount: Int
        let trackName: String
        let trackColor: Color
        let durationSeconds: Double
        let tempo: Int?
        let key: String
    }

    private var sampleItems: [SampleItem] {
        // Group all clips in arrangement by sample reference
        var clipCounts: [String: Int] = [:]
        var primaryTracks: [String: AbletonTrack] = [:]
        var sampleDurations: [String: Double] = [:]

        for track in arrangement.tracks {
            for clip in track.clips {
                guard let sample = clip.sampleRef else { continue }
                let key = sample.fileName
                clipCounts[key, default: 0] += 1
                if primaryTracks[key] == nil {
                    primaryTracks[key] = track
                }
                if sampleDurations[key] == nil {
                    sampleDurations[key] = (clip.durationBeats / max(20.0, arrangement.tempo)) * 60.0
                }
            }
        }

        var unique: [String: AbletonSampleRef] = [:]
        for sample in arrangement.sampleRefs {
            if unique[sample.fileName] == nil {
                unique[sample.fileName] = sample
            }
        }

        return unique.values.map { sample in
            let fileURL = resolveFileURL(for: sample)
            let isMissing = sample.isMissing || (fileURL == nil)
            let used = max(1, clipCounts[sample.fileName] ?? 1)
            let track = primaryTracks[sample.fileName]
            let duration = getAudioDuration(fileURL: fileURL, fallback: sampleDurations[sample.fileName] ?? 1.5)
            let tempo = extractTempo(from: sample.fileName)
            let key = extractKey(from: sample.fileName)

            return SampleItem(
                id: sample.id,
                sample: sample,
                fileName: sample.fileName,
                fileURL: fileURL,
                isMissing: isMissing,
                usedCount: used,
                trackName: track?.name ?? "Audio",
                trackColor: track?.color ?? Color.accent,
                durationSeconds: duration,
                tempo: tempo,
                key: key
            )
        }.sorted { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }
    }

    private var displayedItems: [SampleItem] {
        sampleItems.filter { item in
            if filterMissingOnly && !item.isMissing { return false }
            if !searchText.isEmpty {
                let text = searchText.lowercased()
                return item.fileName.lowercased().contains(text) ||
                       item.trackName.lowercased().contains(text) ||
                       item.key.lowercased().contains(text)
            }
            return true
        }
    }

    private var missingCount: Int {
        sampleItems.filter(\.isMissing).count
    }

    public var body: some View {
        VStack(spacing: 0) {
            // ── Toolbar Header ───────────────────────────────────────────────
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(missingCount > 0 ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    Text(missingCount > 0 ? "\(missingCount) missing samples" : "All \(sampleItems.count) samples collected & present")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(missingCount > 0 ? .orange : .primaryText)
                }

                Spacer()

                Toggle("Missing only", isOn: $filterMissingOnly)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .foregroundColor(.secondaryText)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(.tertiaryText)
                    TextField("Search samples...", text: $searchText)
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

                Text("Name")
                    .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

                Text("Waveform")
                    .frame(width: 145, alignment: .leading)

                Text("Length")
                    .frame(width: 65, alignment: .trailing)

                Text("Tempo")
                    .frame(width: 55, alignment: .trailing)

                Text("Key")
                    .frame(width: 65, alignment: .trailing)

                Text("Track")
                    .frame(width: 130, alignment: .leading)
                    .padding(.leading, 8)

                Text("Used")
                    .frame(width: 45, alignment: .trailing)

                Spacer().frame(width: 28) // Action / reveal space
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.tertiaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(Color(red: 0.08, green: 0.085, blue: 0.10))

            Divider().background(Color.divider)

            // ── Samples List ─────────────────────────────────────────────────
            if displayedItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 26))
                        .foregroundColor(.tertiaryText)
                    Text("No samples found")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(displayedItems) { item in
                            sampleRow(item)
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

    // MARK: - Sample Row

    private func sampleRow(_ item: SampleItem) -> some View {
        let isHovered = hoveredSampleId == item.id
        let isPlaying = samplePlayer.isPlaying && samplePlayer.currentSampleId == item.id

        return HStack(spacing: 8) {
            // 1. Play / Preview button
            Button {
                if let url = item.fileURL {
                    samplePlayer.toggle(sampleId: item.id, url: url)
                }
            } label: {
                Image(systemName: isPlaying ? "stop.fill" : (item.isMissing ? "play.slash.fill" : "play.fill"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isPlaying ? .white : (item.isMissing ? Color.secondaryText.opacity(0.4) : Color.white.opacity(0.85)))
                    .frame(width: 22, height: 22)
                    .background(
                        Circle().fill(isPlaying ? Color.accent : (isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.06)))
                    )
            }
            .buttonStyle(.plain)
            .disabled(item.isMissing || item.fileURL == nil)
            .help(item.isMissing ? "Sample file is missing" : (isPlaying ? "Stop preview" : "Audition sample audio"))

            // 2. Drag Handle (DAWbro style)
            Image(systemName: "circle.grid.2x3.fill")
                .font(.system(size: 9))
                .foregroundColor(isHovered ? .secondaryText : Color.white.opacity(0.2))
                .frame(width: 18)
                .contentShape(Rectangle())
                .onDrag {
                    if let url = item.fileURL {
                        return NSItemProvider(contentsOf: url) ?? NSItemProvider()
                    }
                    return NSItemProvider()
                }
                .help("Drag sample into Ableton Live or Finder")

            // 3. Name & Audio icon
            HStack(spacing: 6) {
                Image(systemName: item.isMissing ? "exclamationmark.triangle.fill" : "waveform")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(item.isMissing ? .orange : Color.accent.opacity(0.85))
                    .frame(width: 14)

                Text(item.fileName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(item.isMissing ? Color.orange.opacity(0.9) : .primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if item.isMissing {
                    Text("MISSING")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                }
            }
            .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

            // 4. Waveform Canvas (DAWbro amber oscilloscope style)
            SampleRowWaveformCanvas(
                fileName: item.fileName,
                trackName: item.trackName,
                isMissing: item.isMissing,
                isPlaying: isPlaying,
                progress: isPlaying ? samplePlayer.playbackProgress : 0.0
            )
            .frame(width: 145, height: 22)

            // 5. Length
            Text(String(format: "%.2f s", item.durationSeconds))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondaryText)
                .frame(width: 65, alignment: .trailing)

            // 6. Tempo
            Text(item.tempo != nil ? "\(item.tempo!)" : "unknown")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(item.tempo != nil ? .primaryText : .tertiaryText)
                .frame(width: 55, alignment: .trailing)

            // 7. Key
            Text(item.key)
                .font(.system(size: 11, weight: item.key != "unknown" ? .medium : .regular, design: .monospaced))
                .foregroundColor(item.key != "unknown" ? .accent : .tertiaryText)
                .frame(width: 65, alignment: .trailing)

            // 8. Track (with color indicator)
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

            // 9. Used Count badge (e.g. 4x, 63x)
            Text("\(item.usedCount)x")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.secondaryText)
                .frame(width: 32)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 3.5))
                .frame(width: 45, alignment: .trailing)

            // 10. Reveal in Finder button
            if let url = item.fileURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundColor(isHovered ? .secondaryText : .clear)
                }
                .buttonStyle(.plain)
                .frame(width: 22)
                .help("Reveal in Finder")
            } else {
                Spacer().frame(width: 22)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.white.opacity(0.035) : (isPlaying ? Color.accent.opacity(0.08) : Color.clear))
        )
        .onHover { h in
            hoveredSampleId = h ? item.id : nil
        }
    }

    // MARK: - Helpers

    private func resolveFileURL(for sample: AbletonSampleRef) -> URL? {
        if let abs = sample.absolutePath, FileManager.default.fileExists(atPath: abs) {
            return URL(fileURLWithPath: abs)
        }
        if let rel = sample.relativePath {
            let candidate = project.folderURL.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func getAudioDuration(fileURL: URL?, fallback: Double) -> Double {
        if let url = fileURL {
            let asset = AVURLAsset(url: url)
            let secs = CMTimeGetSeconds(asset.duration)
            if secs.isFinite && secs > 0 {
                return secs
            }
        }
        return fallback
    }

    private func extractTempo(from fileName: String) -> Int? {
        let lower = fileName.lowercased()
        if let match = lower.range(of: #"\b(\d{2,3})\s*bpm\b"#, options: .regularExpression) {
            let numStr = lower[match].replacingOccurrences(of: "bpm", with: "").trimmingCharacters(in: .whitespaces)
            return Int(numStr)
        }
        if let match = lower.range(of: #"(?:^|[\s_])(1[1-7]\d)(?:[\s_]|$)"#, options: .regularExpression) {
            let digits = lower[match].trimmingCharacters(in: CharacterSet.decimalDigits.inverted)
            return Int(digits)
        }
        if lower.contains("loop") || lower.contains("break") {
            return Int(round(arrangement.tempo))
        }
        return nil
    }

    private func extractKey(from fileName: String) -> String {
        let clean = fileName
            .replacingOccurrences(of: ".wav", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ".aif", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ".mp3", with: "", options: .caseInsensitive)

        let pattern = #"(?:^|[\s_\-#])([A-G][b#]?(?:m|min|maj|minor|major)?)(?:[\s_\-#]|$)"#
        if let match = clean.range(of: pattern, options: .regularExpression) {
            let raw = String(clean[match]).trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            if !raw.isEmpty && raw.count <= 6 {
                return raw
            }
        }
        return "unknown"
    }
}

// MARK: - Sample Row Waveform Canvas (DAWbro style amber oscilloscope)

struct SampleRowWaveformCanvas: View {
    let fileName: String
    let trackName: String
    let isMissing: Bool
    let isPlaying: Bool
    let progress: Double

    var body: some View {
        Canvas { context, size in
            guard size.width > 4, size.height > 4 else { return }

            let midY = size.height / 2.0
            let maxAmp = (size.height / 2.0) - 1.0

            // Faint zero-crossing center guideline
            var centerLine = Path()
            centerLine.move(to: CGPoint(x: 0, y: midY))
            centerLine.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(centerLine, with: .color(Color.white.opacity(0.08)), lineWidth: 0.5)

            let combined = (fileName + " " + trackName).lowercased()
            let isTransient = combined.contains("kick") || combined.contains("drum") ||
                              combined.contains("clap") || combined.contains("snare") ||
                              combined.contains("hat") || combined.contains("perc") ||
                              combined.contains("shot") || combined.contains("hit")
            let isNoise = combined.contains("white") || combined.contains("noise") || combined.contains("sweep") || combined.contains("riser")
            let isVocalOrLoop = combined.contains("vocal") || combined.contains("loop") || combined.contains("synth") || combined.contains("bass")

            let step: CGFloat = 2.0
            let count = Int(size.width / step)
            let seed = UInt32(bitPattern: Int32(truncatingIfNeeded: fileName.hashValue))

            var wavePath = Path()

            for i in 0..<count {
                let x = CGFloat(i) * step
                let p = x / size.width
                let noise = CGFloat((seed &+ UInt32(i * 17)) % 100) / 100.0

                let amp: CGFloat
                if isTransient {
                    // Sharp transient burst pulses with decays
                    let pulseProgress = (p * 4.0).truncatingRemainder(dividingBy: 1.0)
                    let env = exp(-pulseProgress * 7.0)
                    amp = max(1.2, maxAmp * (0.15 + 0.8 * env + 0.05 * noise))
                } else if isNoise {
                    // White noise riser slope or decay
                    let slope = p
                    amp = max(1.0, maxAmp * (0.1 + 0.85 * slope * noise))
                } else if isVocalOrLoop {
                    // Undulating multi-harmonic acoustic profile
                    let w1 = sin(p * 3.14159 * 5.0)
                    let w2 = cos(p * 3.14159 * 2.0)
                    let env = max(0.1, 0.4 + 0.35 * abs(w1) + 0.25 * abs(w2))
                    amp = max(1.2, maxAmp * (env * 0.85 + noise * 0.15))
                } else {
                    let w = sin(p * 3.14159 * 4.0)
                    amp = max(1.0, maxAmp * (0.2 + 0.65 * abs(w) + 0.15 * noise))
                }

                wavePath.move(to: CGPoint(x: x, y: midY - amp))
                wavePath.addLine(to: CGPoint(x: x, y: midY + amp))
            }

            let waveColor = isMissing
                ? Color.orange.opacity(0.4)
                : Color(red: 0.98, green: 0.58, blue: 0.15) // Amber/orange matching DAWbro

            context.stroke(wavePath, with: .color(waveColor), lineWidth: 1.1)

            // Real-time playback playhead
            if isPlaying && progress > 0.0 {
                let playheadX = CGFloat(progress) * size.width
                var ph = Path()
                ph.move(to: CGPoint(x: playheadX, y: 0))
                ph.addLine(to: CGPoint(x: playheadX, y: size.height))
                context.stroke(ph, with: .color(Color.white), lineWidth: 1.5)
            }
        }
        .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 3))
    }
}
