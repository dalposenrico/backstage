import SwiftUI
import AVFoundation

/// DAW-styled playable interactive waveform embedded in the project detail header.
/// Shows the newest audio export's waveform with play/pause control and scrubbable timeline.
struct ProjectHeaderWaveformView: View {
    let track: Track
    let project: Project
    @EnvironmentObject private var player: AudioPlayer
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ProjectHeaderWaveformTimelineView(
            track: track,
            project: project,
            timeline: player.timeline,
            player: player,
            store: store
        )
    }
}

private struct ProjectHeaderWaveformTimelineView: View {
    let track: Track
    let project: Project
    @ObservedObject var timeline: PlaybackTimeline
    @ObservedObject var player: AudioPlayer
    let store: AppStore

    @State private var samples: [Float]? = nil
    @State private var isHovered = false
    @State private var hoverFraction: Double? = nil
    @State private var isDragging = false
    @State private var dragFraction: Double = 0

    private var isCurrentTrack: Bool {
        player.currentTrack?.id == track.id
    }

    private var isPlaying: Bool {
        isCurrentTrack && player.isPlaying
    }

    private var currentProgress: Double {
        if isDragging { return dragFraction }
        if isCurrentTrack { return timeline.progress }
        return 0
    }

    // Warm amber DAW accent color matching arrangement & sample tabs
    private let waveformColor = Color(hex: "FF9500")

    var body: some View {
        HStack(spacing: 7) {
            // Circular Play / Pause Button
            Button {
                if isCurrentTrack {
                    player.togglePlayPause()
                } else {
                    store.playTrack(track)
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(waveformColor.opacity(isPlaying ? 0.28 : 0.16))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(waveformColor.opacity(isPlaying ? 0.75 : 0.40), lineWidth: 1)
                        )

                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(waveformColor)
                        .offset(x: isPlaying ? 0 : 0.8)
                }
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Pause" : "Play \(track.displayName)")

            // Interactive Waveform Canvas
            let bars = samples ?? placeholderBars
            GeometryReader { geo in
                let size = geo.size
                let count = bars.count
                let progress = max(0, min(1, currentProgress))
                let progressX = size.width * CGFloat(progress)
                let hoverX = hoverFraction.map { size.width * CGFloat($0) }

                Canvas { context, canvasSize in
                    guard !bars.isEmpty else { return }
                    let totalSpacing: CGFloat = CGFloat(count - 1) * 1.6
                    let barWidth = max(1.5, (canvasSize.width - totalSpacing) / CGFloat(count))
                    let midY = canvasSize.height / 2.0

                    for index in 0..<count {
                        let x = CGFloat(index) * (barWidth + 1.6)
                        let amp = CGFloat(max(0.0, min(1.0, bars[index])))

                        let isPlayed = isCurrentTrack && x <= progressX
                        let barColor = isPlayed
                            ? waveformColor
                            : waveformColor.opacity(0.42)

                        if amp <= 0.01 {
                            // Silent segment: straight horizontal line running along the center
                            let silentRect = CGRect(
                                x: x,
                                y: midY - 0.75,
                                width: barWidth + (index < count - 1 ? 1.6 : 0),
                                height: 1.5
                            )
                            context.fill(Path(silentRect), with: .color(barColor.opacity(0.45)))
                        } else {
                            let barHeight = max(2.5, amp * (canvasSize.height - 4))
                            let rect = CGRect(
                                x: x,
                                y: midY - barHeight / 2.0,
                                width: barWidth,
                                height: barHeight
                            )
                            context.fill(Path(roundedRect: rect, cornerRadius: 0.8), with: .color(barColor))
                        }
                    }

                    // Playhead indicator line
                    if isCurrentTrack && progress > 0 {
                        var playhead = Path()
                        playhead.move(to: CGPoint(x: progressX, y: 1))
                        playhead.addLine(to: CGPoint(x: progressX, y: canvasSize.height - 1))
                        context.stroke(playhead, with: .color(.white), lineWidth: 1.5)
                    }

                    // Hover position line
                    if let hx = hoverX, isHovered && !isDragging {
                        var hoverLine = Path()
                        hoverLine.move(to: CGPoint(x: hx, y: 2))
                        hoverLine.addLine(to: CGPoint(x: hx, y: canvasSize.height - 2))
                        context.stroke(hoverLine, with: .color(.white.opacity(0.45)), lineWidth: 1)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.28))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(waveformColor.opacity(isHovered ? 0.35 : 0.15), lineWidth: 0.8)
                )
                .contentShape(Rectangle())
                .onHover { isHovering in
                    isHovered = isHovering
                    if !isHovering { hoverFraction = nil }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            isDragging = true
                            let frac = max(0, min(1, val.location.x / size.width))
                            dragFraction = frac
                            hoverFraction = frac
                        }
                        .onEnded { val in
                            let frac = max(0, min(1, val.location.x / size.width))
                            isDragging = false
                            seekTo(fraction: frac)
                        }
                )
            }
            .frame(width: 210, height: 24)
            .help("\(track.displayName)")
        }
        .onAppear {
            loadSamples()
        }
        .onChange(of: track.url) { _, _ in
            loadSamples()
        }
    }

    private func seekTo(fraction: Double) {
        if isCurrentTrack && player.duration > 0 {
            let targetTime = fraction * player.duration
            player.seek(to: targetTime)
            if !player.isPlaying {
                player.togglePlayPause()
            }
        } else {
            Task {
                let asset = AVURLAsset(url: track.url)
                let durationSeconds = (try? await asset.load(.duration))?.seconds ?? 0
                let targetTime = fraction * durationSeconds
                await MainActor.run {
                    player.play(track, startAt: targetTime > 0 ? targetTime : 0)
                }
            }
        }
    }

    private func loadSamples() {
        if let cached = InlineWaveformCache.shared.cached(for: track.url) {
            self.samples = cached
        } else {
            InlineWaveformCache.shared.requestSamples(for: track.url) { loaded in
                self.samples = loaded
            }
        }
    }

    private var placeholderBars: [Float] {
        [Float](repeating: 0.0, count: 32)
    }
}
