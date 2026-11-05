import SwiftUI
import AVFoundation

struct ComparisonPlayerBarView: View {
    @ObservedObject var controller: ComparisonAudioPlayer
    var sourcesOverride: [CompareSource]? = nil
    var loudnessResultsOverride: [String: LoudnessResult]? = nil
    var markersOverride: [ComparisonMarker]? = nil
    var onToggleLoop: (() -> Void)? = nil

    @State private var isDraggingSeek = false
    @State private var dragSeekFraction: Double = 0
    @State private var hoverSeekFraction: Double? = nil

    private var sources: [CompareSource] {
        sourcesOverride ?? controller.sources
    }

    private var loudnessResults: [String: LoudnessResult] {
        loudnessResultsOverride ?? controller.loudnessResults
    }

    private var markers: [ComparisonMarker] {
        markersOverride ?? controller.markers
    }

    private var activeSource: CompareSource? {
        controller.activeSource
    }

    private var activeLetter: String {
        guard let active = activeSource else { return "—" }
        return controller.versionLetter(for: active, in: sources)
    }

    private var previousLetter: String {
        guard let prev = controller.previousSource else {
            // If only 2 sources, pick the other one
            if sources.count == 2, let active = activeSource {
                let other = sources.first { $0 != active }
                return other.map { controller.versionLetter(for: $0, in: sources) } ?? "B"
            }
            return "B"
        }
        return controller.versionLetter(for: prev, in: sources)
    }

    private var displayedProgress: Double {
        if isDraggingSeek { return dragSeekFraction }
        return controller.progress
    }

    private var displayedCurrentTime: TimeInterval {
        if isDraggingSeek { return dragSeekFraction * controller.duration }
        return controller.currentTime
    }

    var body: some View {
        VStack(spacing: 0) {
            // Full-width Scrubbing Seek Bar
            seekBarView

            // Main transport & A/B comparison control bar
            HStack(spacing: 12) {
                // Left: Active Version Badge & Details
                leftVersionInfo
                    .frame(minWidth: 160, maxWidth: 280, alignment: .leading)

                Spacer(minLength: 4)

                // Center: Transport & Instant A/B Switching
                centerTransportControls

                Spacer(minLength: 4)

                // Right: Time, Gain Match Toggle & Volume
                rightUtilityControls
                    .frame(minWidth: 220, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(height: 56)
        .background(Color(hex: "121417"))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)
        }
        .alert("Playback Problem", isPresented: Binding(
            get: { controller.playbackError != nil },
            set: { if !$0 { controller.playbackError = nil } }
        )) {
            Button("OK", role: .cancel) { controller.playbackError = nil }
        } message: {
            Text(controller.playbackError ?? "")
        }
    }

    // MARK: - Seek Bar

    private var seekBarView: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let progressX = CGFloat(min(max(displayedProgress, 0), 1)) * width

            ZStack(alignment: .leading) {
                // Track background
                Rectangle()
                    .fill(Color(hex: "1A1D21"))
                    .frame(height: 8)

                // Markers overlay
                ForEach(markers) { marker in
                    if let pos = marker.position(for: activeSource?.url.path ?? "", legacySourcePath: nil)
                        ?? (marker.origin == .ableton ? marker.fraction : marker.sourceFractions.values.first) {
                        Rectangle()
                            .fill(Color(hex: "FF9F0A").opacity(0.55))
                            .frame(width: 1.5, height: 8)
                            .offset(x: CGFloat(pos) * width)
                    }
                }

                // Played bar
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "FF9F0A"), Color(hex: "FFB340")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: progressX, height: 8)

                // Hover preview line
                if let hover = hoverSeekFraction {
                    Rectangle()
                        .fill(Color.white.opacity(0.45))
                        .frame(width: 1.5, height: 8)
                        .offset(x: CGFloat(hover) * width)
                }

                // Thumb / Playhead indicator
                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .offset(x: max(0, min(width - 10, progressX - 5)))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDraggingSeek = true
                        let fraction = min(max(Double(value.location.x / width), 0), 1)
                        dragSeekFraction = fraction
                    }
                    .onEnded { value in
                        let fraction = min(max(Double(value.location.x / width), 0), 1)
                        isDraggingSeek = false
                        controller.seek(toFraction: fraction)
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    hoverSeekFraction = min(max(Double(point.x / width), 0), 1)
                case .ended:
                    hoverSeekFraction = nil
                }
            }
        }
        .frame(height: 8)
    }

    // MARK: - Left: Active Track Details

    private var leftVersionInfo: some View {
        HStack(spacing: 9) {
            if let active = activeSource {
                // Version Letter Badge
                Text(activeLetter)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(.black)
                    .frame(width: 20, height: 20)
                    .background(Color(hex: "FF9F0A"), in: RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(active.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        if active.isReference {
                            Text("REF")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "30D158"))
                                .padding(.horizontal, 3.5)
                                .padding(.vertical, 1)
                                .background(Color(hex: "30D158").opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                        }
                    }

                    HStack(spacing: 6) {
                        Text(active.kind)
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondaryText)

                        if let loudness = loudnessResults[active.url.path] {
                            Text("·")
                                .font(.system(size: 9))
                                .foregroundColor(.tertiaryText)
                            Text(String(format: "%.1f LUFS", loudness.integratedLUFS))
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundColor(.secondaryText)
                        }

                        if abs(controller.appliedGainDB) >= 0.05 {
                            Text(String(format: "%+.1f dB", controller.appliedGainDB))
                                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(hex: "FF9F0A"))
                                .padding(.horizontal, 3.5)
                                .padding(.vertical, 0.5)
                                .background(Color(hex: "FF9F0A").opacity(0.14), in: RoundedRectangle(cornerRadius: 2.5))
                        }
                    }
                    .lineLimit(1)
                }
            } else {
                Text("Select a version to audition")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.secondaryText)
            }
        }
    }

    // MARK: - Center: Transport & A/B Switching

    private var centerTransportControls: some View {
        HStack(spacing: 12) {
            // Previous version button
            Button {
                controller.switchPrevious(allSources: sources, loudnessResults: loudnessResults)
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(sources.count > 1 ? .white : Color.white.opacity(0.25))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(sources.count <= 1)
            .help("Previous version at current playhead (↑)")

            // Instant A/B Toggle Button
            Button {
                controller.toggleAB(allSources: sources, loudnessResults: loudnessResults)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("A / B")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                    Text("(\(activeLetter)⇄\(previousLetter))")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.6))
                }
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: "FF9F0A").opacity(0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(hex: "FF9F0A").opacity(0.7), lineWidth: 1)
                )
                .foregroundColor(Color(hex: "FF9F0A"))
            }
            .buttonStyle(.plain)
            .disabled(sources.count <= 1)
            .help("Instant A/B switch at the exact current drop / timestamp (Tab or \\)")

            // Big Play / Pause Button
            Button {
                controller.togglePlayPause(allSources: sources, loudnessResults: loudnessResults)
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(hex: "FF9F0A"))
                        .frame(width: 36, height: 36)
                        .shadow(color: Color(hex: "FF9F0A").opacity(0.35), radius: 4, y: 1)

                    Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.black)
                        .offset(x: controller.isPlaying ? 0 : 1)
                }
            }
            .buttonStyle(.plain)
            .help(controller.isPlaying ? "Pause (Space)" : "Play (Space)")

            // Next version button
            Button {
                controller.switchNext(allSources: sources, loudnessResults: loudnessResults)
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(sources.count > 1 ? .white : Color.white.opacity(0.25))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(sources.count <= 1)
            .help("Next version at current playhead (↓)")

            // Quick Version Pills (instant switch at same playhead)
            if sources.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(sources.prefix(8).enumerated()), id: \.element.url) { index, source in
                            let letter = ComparisonAudioPlayer.versionLetter(for: index)
                            let isSelected = activeSource == source
                            Button {
                                controller.switchTo(
                                    source,
                                    allSources: sources,
                                    loudnessResults: loudnessResults,
                                    keepPosition: true
                                )
                            } label: {
                                HStack(spacing: 3) {
                                    Text(letter)
                                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                        .foregroundColor(isSelected ? .black : Color(hex: "FF9F0A"))
                                    Text(source.name)
                                        .font(.system(size: 9.5, weight: isSelected ? .bold : .medium))
                                        .lineLimit(1)
                                        .frame(maxWidth: 80)
                                }
                                .padding(.horizontal, 6)
                                .frame(height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 4.5)
                                        .fill(isSelected ? Color(hex: "FF9F0A") : Color.white.opacity(0.06))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4.5)
                                        .stroke(isSelected ? Color(hex: "FF9F0A") : Color.white.opacity(0.12), lineWidth: 0.8)
                                )
                                .foregroundColor(isSelected ? .black : .white)
                            }
                            .buttonStyle(.plain)
                            .help("Switch to \(letter): \(source.name) at exact current timestamp")
                        }
                    }
                }
                .frame(maxWidth: 300)
                .padding(.leading, 6)
            }
        }
    }

    // MARK: - Right: Time & Volume

    private var rightUtilityControls: some View {
        HStack(spacing: 14) {
            // Gain match toggle pill
            Button {
                controller.setGainMatch(!controller.gainMatch, loudnessResults: loudnessResults)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "equalizer")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text("GAIN MATCH")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 6)
                .frame(height: 22)
                .background(
                    controller.gainMatch
                        ? Color(hex: "30D158").opacity(0.18)
                        : Color.white.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            controller.gainMatch
                                ? Color(hex: "30D158").opacity(0.6)
                                : Color.white.opacity(0.14),
                            lineWidth: 0.8
                        )
                )
                .foregroundColor(controller.gainMatch ? Color(hex: "30D158") : Color.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .help("Gain match levels audio so loudness differences don't bias your A/B comparison")

            // Time label: Current / Duration
            HStack(spacing: 2) {
                Text(formatTime(displayedCurrentTime))
                    .foregroundColor(.white)
                Text("/")
                    .foregroundColor(.tertiaryText)
                Text(formatTime(controller.duration))
                    .foregroundColor(.secondaryText)
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))

            // Volume control
            HStack(spacing: 5) {
                Button {
                    controller.setVolume(controller.volume > 0 ? 0 : 0.8)
                } label: {
                    Image(systemName: controller.volume == 0 ? "speaker.slash.fill" : (controller.volume < 0.5 ? "speaker.1.fill" : "speaker.wave.2.fill"))
                        .font(.system(size: 10))
                        .foregroundColor(controller.volume == 0 ? Color(hex: "FF453A") : .secondaryText)
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { Double(controller.volume) },
                        set: { controller.setVolume(Float($0)) }
                    ),
                    in: 0...1
                )
                .frame(width: 64)
                .tint(Color(hex: "FF9F0A"))
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard !seconds.isNaN && !seconds.isInfinite && seconds >= 0 else { return "00:00.0" }
        let totalTenths = Int((seconds * 10).rounded())
        let tenths = totalTenths % 10
        let totalSeconds = totalTenths / 10
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d.%1d", mins, secs, tenths)
    }
}
