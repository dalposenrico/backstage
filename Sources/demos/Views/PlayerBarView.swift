import SwiftUI

struct PlayerBarView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var player: AudioPlayer

    var body: some View {
        VStack(spacing: 0) {
            // Seek bar (full width, sits right on the divider)
            TimelineSeekBar(
                timeline: player.timeline,
                trackURL: player.currentTrack?.url,
                onSeek: { p in player.seek(to: p * player.duration) }
            )

            HStack(spacing: 0) {
                // Left: track info
                Group {
                    if let track = player.currentTrack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.displayName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primaryText)
                                .lineLimit(1)
                            if let project = store.projects.first(where: { p in
                                p.tracks.contains { $0.id == track.id }
                            }) {
                                Text(project.name)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                        .transition(.opacity)
                    } else {
                        Text("—")
                            .font(.system(size: 13))
                            .foregroundColor(.tertiaryText)
                    }
                }
                .frame(width: 200, alignment: .leading)
                .animation(.easeInOut(duration: 0.2), value: player.currentTrack?.id)

                Spacer()

                // Center: controls
                HStack(spacing: 32) {
                    Button(action: store.playPrevious) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 15))
                            .foregroundColor(player.currentTrack == nil ? .tertiaryText : .primaryText)
                    }
                    .buttonStyle(.plain)
                    .disabled(player.currentTrack == nil)

                    // Play / pause button — inverted bg so it pops in both modes
                    Button(action: { player.togglePlayPause() }) {
                        ZStack {
                            Circle()
                                .fill(Color.playBtnBg)
                                .frame(width: 42, height: 42)
                            if player.isLoading {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 17))
                                    .foregroundColor(.playBtnFg)
                                    .offset(x: player.isPlaying ? 0 : 1.5)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(player.currentTrack == nil || player.isLoading)
                    .opacity(player.currentTrack == nil ? 0.3 : 1)

                    Button(action: store.playNext) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 15))
                            .foregroundColor(player.currentTrack == nil ? .tertiaryText : .primaryText)
                    }
                    .buttonStyle(.plain)
                    .disabled(player.currentTrack == nil)
                }

                Spacer()

                // Right: time + volume
                HStack(spacing: 14) {
                    PlaybackTimeLabel(timeline: player.timeline)

                    HStack(spacing: 6) {
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.tertiaryText)
                        Slider(
                            value: Binding(
                                get: { Double(player.volume) },
                                set: { player.setVolume(Float($0)) }
                            )
                        )
                        .frame(width: 72)
                        .tint(.accent)
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.tertiaryText)
                    }
                }
                .frame(width: 200, alignment: .trailing)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
        }
        .background(Color.playerBg)
        .alert("Playback Problem", isPresented: Binding(
            get: { player.playbackError != nil },
            set: { if !$0 { player.playbackError = nil } }
        )) {
            Button("OK", role: .cancel) { player.playbackError = nil }
        } message: {
            Text(player.playbackError ?? "")
        }
    }
}

struct TimelineSeekBar: View {
    @ObservedObject var timeline: PlaybackTimeline
    let trackURL: URL?
    let onSeek: (Double) -> Void

    var body: some View {
        SeekBar(progress: timeline.progress, trackURL: trackURL, onSeek: onSeek)
    }
}

struct PlaybackTimeLabel: View {
    @ObservedObject var timeline: PlaybackTimeline

    var body: some View {
        Text("\(timeline.currentTime.mmss) / \(timeline.duration.mmss)")
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondaryText)
            .frame(width: 90, alignment: .trailing)
            .animation(.none, value: timeline.currentTime)
    }
}

struct SeekBar: View {
    let progress: Double
    let trackURL: URL?
    let onSeek: (Double) -> Void

    @State private var isHovered = false
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var waveform: [SpectralWaveformSample] = []

    var display: Double { isDragging ? dragProgress : progress }

    var barHeight: CGFloat { (isHovered || isDragging) ? 4 : 2 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                if waveform.isEmpty {
                    Rectangle().fill(Color.seekTrack).frame(height: barHeight)
                    Rectangle().fill(Color.accent)
                        .frame(width: geo.size.width * max(0, min(1, display)), height: barHeight)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.white.opacity(0.025))
                        SpectralWaveformView(
                            samples: waveform,
                            playedFraction: display
                        )
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                    }
                    .frame(height: 34)
                }

                // Thumb
                if isHovered || isDragging {
                    Circle()
                        .fill(Color.playBtnBg)
                        .frame(width: 11, height: 11)
                        .offset(x: geo.size.width * max(0, min(1, display)) - 5.5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        dragProgress = max(0, min(1, value.location.x / geo.size.width))
                    }
                    .onEnded { value in
                        let p = max(0, min(1, value.location.x / geo.size.width))
                        isDragging = false
                        onSeek(p)
                    }
            )
        }
        .frame(height: 38)
        .task(id: trackURL) {
            waveform = []
            if let trackURL { waveform = await WaveformSampler.spectralSamples(for: trackURL) }
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}
