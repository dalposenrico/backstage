import SwiftUI
import AVFoundation

/// Lightweight in-memory cache for project row waveform samples to keep list scrolling at 120fps.
@MainActor
final class InlineWaveformCache: ObservableObject {
    static let shared = InlineWaveformCache()
    @Published private(set) var samplesByPath: [String: [Float]] = [:]
    private var inFlight = Set<String>()

    func samples(for url: URL) -> [Float]? {
        samplesByPath[url.path]
    }

    func requestSamples(for url: URL, barCount: Int = 48) {
        let path = url.path
        guard samplesByPath[path] == nil, !inFlight.contains(path) else { return }
        inFlight.insert(path)

        Task.detached(priority: .utility) {
            let result = await WaveformSampler.samples(for: url, count: barCount)
            await MainActor.run {
                self.samplesByPath[path] = result
                self.inFlight.remove(path)
            }
        }
    }
}

/// DAWbro-style inline audio waveform with quick-play button and progress indicator for project rows.
struct InlineProjectWaveformView: View {
    let track: Track
    let isPlaying: Bool
    let progress: Double
    let onPlayToggle: () -> Void

    @ObservedObject private var cache = InlineWaveformCache.shared

    var body: some View {
        HStack(spacing: 6) {
            // Play / Pause button
            Button(action: onPlayToggle) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle().fill(isPlaying ? Color.accent : Color.white.opacity(0.18))
                    )
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Pause" : "Play \(track.displayName)")

            // Mini Waveform Canvas
            let bars = cache.samples(for: track.url) ?? placeholderBars
            GeometryReader { geo in
                Canvas { context, size in
                    guard !bars.isEmpty else { return }
                    let count = bars.count
                    let totalSpacing: CGFloat = CGFloat(count - 1) * 1.5
                    let barWidth = max(1.0, (size.width - totalSpacing) / CGFloat(count))
                    let midY = size.height / 2.0
                    let progressWidth = size.width * CGFloat(progress)

                    for index in 0..<count {
                        let x = CGFloat(index) * (barWidth + 1.5)
                        let amp = CGFloat(max(0.08, min(1.0, bars[index])))
                        let barHeight = max(2.0, amp * size.height * 0.9)
                        let rect = CGRect(
                            x: x,
                            y: midY - barHeight / 2.0,
                            width: barWidth,
                            height: barHeight
                        )

                        let isPastProgress = isPlaying && x <= progressWidth
                        let barColor: Color = isPastProgress
                            ? Color.accent
                            : Color.accent.opacity(0.55)

                        context.fill(Path(roundedRect: rect, cornerRadius: 0.8), with: .color(barColor))
                    }
                }
            }
            .frame(width: 90, height: 22)
            .contentShape(Rectangle())
            .onTapGesture {
                onPlayToggle()
            }
        }
        .onAppear {
            cache.requestSamples(for: track.url)
        }
    }

    private var placeholderBars: [Float] {
        [0.2, 0.4, 0.6, 0.5, 0.7, 0.8, 0.6, 0.7, 0.9, 0.7, 0.5, 0.6, 0.4, 0.3, 0.5, 0.7, 0.6, 0.4]
    }
}
