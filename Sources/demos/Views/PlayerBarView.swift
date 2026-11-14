import SwiftUI

struct PlayerBarView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var player: AudioPlayer

    var body: some View {
        let currentProject = player.currentTrack.flatMap { track in
            store.projects.first { p in p.tracks.contains { $0.id == track.id } }
        } ?? store.selectedProject

        return VStack(spacing: 0) {
            // Seek bar (full width, sits right on the divider)
            TimelineSeekBar(
                timeline: player.timeline,
                trackURL: player.currentTrack?.url,
                project: currentProject,
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
                            if let project = currentProject {
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
    let project: Project?
    let onSeek: (Double) -> Void

    var body: some View {
        SeekBar(
            progress: timeline.progress,
            trackURL: trackURL,
            duration: timeline.duration,
            project: project,
            onSeek: onSeek
        )
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
    let duration: Double
    let project: Project?
    let onSeek: (Double) -> Void

    @EnvironmentObject var comparisonMarkers: ComparisonMarkerStore
    @State private var isHovered = false
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var waveform: [SpectralWaveformSample] = []
    @State private var markers: [WaveformSectionMarker] = []
    @State private var hoveredMarkerId: String?
    @State private var zoomScale: CGFloat = 1.0
    @State private var visibleCenter: Double = 0.5
    @State private var autoFollowPlayhead = true
    @State private var hoverFraction: Double? = nil

    var display: Double { isDragging ? dragProgress : progress }

    var barHeight: CGFloat { (isHovered || isDragging) ? 4 : 2 }

    var visibleWindow: (start: Double, end: Double, width: Double) {
        let zoom = max(1.0, Double(zoomScale))
        let width = 1.0 / zoom
        let half = width / 2.0
        let center = min(max(visibleCenter, half), 1.0 - half)
        return (start: max(0.0, center - half), end: min(1.0, center + half), width: width)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                if waveform.isEmpty {
                    Rectangle().fill(Color.seekTrack).frame(height: barHeight)
                    Rectangle().fill(Color.accent)
                        .frame(width: geo.size.width * max(0, min(1, display)), height: barHeight)
                } else {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 0.05, green: 0.06, blue: 0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                            )

                        SpectralWaveformView(
                            samples: waveform,
                            playedFraction: display,
                            hoverFraction: hoverFraction,
                            sectionMarkers: markers.map(\.fraction),
                            zoomScale: zoomScale,
                            visibleCenterFraction: visibleCenter
                        )
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)

                        // Trackpad gesture and interaction area
                        WaveformTrackpadArea(
                            onMagnify: { mag in handleMagnify(mag) },
                            onScroll: { delta in handleScroll(delta, containerWidth: geo.size.width) },
                            onSmartMagnify: { handleSmartMagnify() },
                            onSeek: { frac in handleSeekFraction(frac) },
                            onHover: { frac in
                                let win = visibleWindow
                                hoverFraction = frac.map { win.start + $0 * win.width }
                            },
                            onDragStateChanged: { isDragging = $0 }
                        )

                        // Section marker badges overlaid across top edge
                        let win = visibleWindow
                        ForEach(markers) { marker in
                            if marker.fraction >= win.start && marker.fraction <= win.end {
                                let x = geo.size.width * CGFloat((marker.fraction - win.start) / win.width)
                                let isHoveredBadge = hoveredMarkerId == marker.id

                                Button {
                                    onSeek(marker.fraction)
                                } label: {
                                    HStack(spacing: 2.5) {
                                        Image(systemName: "flag.fill")
                                            .font(.system(size: 6))
                                            .foregroundColor(isHoveredBadge ? .white : .accent)
                                        Text(marker.title)
                                            .font(.system(size: 8, weight: .bold, design: .rounded))
                                            .foregroundColor(isHoveredBadge ? .white : Color.white.opacity(0.9))
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1.5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 3.5)
                                            .fill(isHoveredBadge ? Color.accent.opacity(0.9) : Color.black.opacity(0.75))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3.5)
                                            .stroke(isHoveredBadge ? Color.white : Color.white.opacity(0.2), lineWidth: 0.6)
                                    )
                                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                                }
                                .buttonStyle(.plain)
                                .offset(x: min(max(2, geo.size.width - 65), max(2, x - 4)), y: 4)
                                .onHover { hovering in
                                    hoveredMarkerId = hovering ? marker.id : nil
                                }
                                .help(marker.note.isEmpty ? "\(marker.title) · Click to jump" : "\(marker.title) · \(marker.note) · Click to jump")
                            }
                        }

                        // Floating Zoom HUD (top-right)
                        if isHovered || zoomScale > 1.0 {
                            HStack {
                                Spacer()
                                zoomControlsOverlay
                                    .padding(.trailing, 8)
                                    .padding(.top, 5)
                            }
                        }
                    }
                    .frame(height: 64)
                }

                // Playhead Thumb
                if !waveform.isEmpty {
                    let win = visibleWindow
                    if display >= win.start && display <= win.end {
                        let thumbX = geo.size.width * CGFloat((display - win.start) / win.width)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 12, height: 12)
                            .shadow(color: Color(red: 0.1, green: 0.5, blue: 1.0).opacity(0.8), radius: 4)
                            .offset(x: thumbX - 6)
                            .allowsHitTesting(false)
                    }
                } else if isHovered || isDragging {
                    Circle()
                        .fill(Color.playBtnBg)
                        .frame(width: 11, height: 11)
                        .offset(x: geo.size.width * max(0, min(1, display)) - 5.5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
        }
        .frame(height: waveform.isEmpty ? 16 : 68)
        .onChange(of: progress) { _, newProgress in
            if autoFollowPlayhead && zoomScale > 1.0 && !isDragging {
                let win = visibleWindow
                if newProgress > win.start + win.width * 0.70 || newProgress < win.start + win.width * 0.10 {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        visibleCenter = newProgress
                    }
                }
            }
        }
        .task(id: "\(trackURL?.path ?? "")-\(project?.folderURL.path ?? "")") {
            zoomScale = 1.0
            visibleCenter = 0.5
            autoFollowPlayhead = true
            waveform = []
            markers = []
            guard let trackURL else { return }

            async let wf = WaveformSampler.spectralSamples(for: trackURL)
            async let mk = WaveformMarkerResolver.resolveMarkers(
                for: trackURL,
                duration: duration,
                project: project,
                comparisonMarkers: comparisonMarkers
            )
            let (loadedWf, loadedMk) = await (wf, mk)
            self.waveform = loadedWf
            self.markers = loadedMk
        }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    private var zoomControlsOverlay: some View {
        HStack(spacing: 3) {
            if zoomScale > 1.0 && !autoFollowPlayhead {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        visibleCenter = display
                        autoFollowPlayhead = true
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 6.5))
                        Text("Follow")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.85), in: Capsule())
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .help("Jump back and auto-follow playback position")
            }

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    let next = max(1.0, zoomScale / 1.5)
                    zoomScale = next <= 1.05 ? 1.0 : next
                    if zoomScale == 1.0 {
                        visibleCenter = 0.5
                        autoFollowPlayhead = true
                    }
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 7.5, weight: .bold))
                    .frame(width: 15, height: 15)
                    .background(Color.black.opacity(0.65), in: Circle())
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(zoomScale <= 1.0)
            .opacity(zoomScale <= 1.0 ? 0.35 : 1.0)

            Button {
                handleSmartMagnify()
            } label: {
                Text(zoomScale > 1.0 ? String(format: "%.1fx", zoomScale) : "1.0x")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(zoomScale > 1.0 ? Color.accentColor.opacity(0.35) : Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 3.5))
                    .foregroundColor(zoomScale > 1.0 ? Color.accentColor : Color.white.opacity(0.85))
            }
            .buttonStyle(.plain)
            .help(zoomScale > 1.0 ? "Reset zoom (double-tap trackpad)" : "Pinch trackpad to zoom in")

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    zoomScale = min(12.0, zoomScale * 1.5)
                    if autoFollowPlayhead { visibleCenter = display }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 7.5, weight: .bold))
                    .frame(width: 15, height: 15)
                    .background(Color.black.opacity(0.65), in: Circle())
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(zoomScale >= 12.0)
            .opacity(zoomScale >= 12.0 ? 0.35 : 1.0)
        }
        .padding(2.5)
        .background(Color.black.opacity(0.75), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.6))
    }

    private func handleMagnify(_ magnification: CGFloat) {
        let newZoom = min(12.0, max(1.0, zoomScale * (1.0 + magnification * 1.6)))
        if abs(newZoom - zoomScale) > 0.01 {
            zoomScale = newZoom <= 1.02 ? 1.0 : newZoom
            if zoomScale == 1.0 {
                visibleCenter = 0.5
                autoFollowPlayhead = true
            } else if autoFollowPlayhead {
                visibleCenter = display
            }
        }
    }

    private func handleScroll(_ deltaX: CGFloat, containerWidth: CGFloat) {
        guard zoomScale > 1.0, containerWidth > 0 else { return }
        let win = visibleWindow
        let scrollFraction = Double(-deltaX / containerWidth) * win.width
        let half = win.width / 2.0
        let newCenter = min(max(visibleCenter + scrollFraction, half), 1.0 - half)
        visibleCenter = newCenter
        autoFollowPlayhead = false
    }

    private func handleSmartMagnify() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if zoomScale > 1.0 {
                zoomScale = 1.0
                visibleCenter = 0.5
                autoFollowPlayhead = true
            } else {
                zoomScale = 3.5
                visibleCenter = display
                autoFollowPlayhead = true
            }
        }
    }

    private func handleSeekFraction(_ localXFraction: Double) {
        let win = visibleWindow
        let songFraction = max(0.0, min(1.0, win.start + localXFraction * win.width))
        dragProgress = songFraction
        onSeek(songFraction)
    }
}

// MARK: - AppKit Trackpad & Gesture Handling for 120Hz Precision

struct WaveformTrackpadArea: NSViewRepresentable {
    var onMagnify: (CGFloat) -> Void
    var onScroll: (CGFloat) -> Void
    var onSmartMagnify: () -> Void
    var onSeek: (Double) -> Void
    var onHover: (Double?) -> Void
    var onDragStateChanged: (Bool) -> Void

    func makeNSView(context: Context) -> WaveformTrackpadNSView {
        let view = WaveformTrackpadNSView()
        view.onMagnify = onMagnify
        view.onScroll = onScroll
        view.onSmartMagnify = onSmartMagnify
        view.onSeek = onSeek
        view.onHover = onHover
        view.onDragStateChanged = onDragStateChanged
        return view
    }

    func updateNSView(_ nsView: WaveformTrackpadNSView, context: Context) {
        nsView.onMagnify = onMagnify
        nsView.onScroll = onScroll
        nsView.onSmartMagnify = onSmartMagnify
        nsView.onSeek = onSeek
        nsView.onHover = onHover
        nsView.onDragStateChanged = onDragStateChanged
    }
}

final class WaveformTrackpadNSView: NSView {
    var onMagnify: ((CGFloat) -> Void)?
    var onScroll: ((CGFloat) -> Void)?
    var onSmartMagnify: (() -> Void)?
    var onSeek: ((Double) -> Void)?
    var onHover: ((Double?) -> Void)?
    var onDragStateChanged: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func magnify(with event: NSEvent) {
        onMagnify?(event.magnification)
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.command) {
            let zoomDelta = event.scrollingDeltaY * 0.02
            onMagnify?(zoomDelta)
        } else {
            let delta = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.deltaX * 10
            onScroll?(delta)
        }
    }

    override func smartMagnify(with event: NSEvent) {
        onSmartMagnify?()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onSmartMagnify?()
            return
        }
        let loc = convert(event.locationInWindow, from: nil)
        guard bounds.width > 0 else { return }
        let frac = max(0.0, min(1.0, Double(loc.x / bounds.width)))
        onDragStateChanged?(true)
        onSeek?(frac)
    }

    override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        guard bounds.width > 0 else { return }
        let frac = max(0.0, min(1.0, Double(loc.x / bounds.width)))
        onSeek?(frac)
    }

    override func mouseUp(with event: NSEvent) {
        onDragStateChanged?(false)
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        guard bounds.width > 0 else { return }
        let frac = max(0.0, min(1.0, Double(loc.x / bounds.width)))
        onHover?(frac)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(nil)
    }
}
