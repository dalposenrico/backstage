import Foundation
import AVFoundation

/// Auditions audio samples directly in the Samples tab with zero latency.
@MainActor
public final class SampleAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    public static let shared = SampleAudioPlayer()

    @Published public private(set) var isPlaying = false
    @Published public private(set) var currentSampleId: String?
    @Published public private(set) var playbackProgress: Double = 0.0

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?

    public override init() {
        super.init()
    }

    public func play(sampleId: String, url: URL) {
        stop()

        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            p.play()
            self.player = p
            self.isPlaying = true
            self.currentSampleId = sampleId
            self.playbackProgress = 0.0

            progressTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, let player = self.player, player.isPlaying, player.duration > 0 else { return }
                    self.playbackProgress = player.currentTime / player.duration
                }
            }
        } catch {
            print("Failed to play sample: \(error.localizedDescription)")
            stop()
        }
    }

    public func stop() {
        progressTimer?.invalidate()
        progressTimer = nil
        if let p = player, p.isPlaying {
            p.stop()
        }
        player = nil
        isPlaying = false
        currentSampleId = nil
        playbackProgress = 0.0
    }

    public func toggle(sampleId: String, url: URL) {
        if isPlaying && currentSampleId == sampleId {
            stop()
        } else {
            play(sampleId: sampleId, url: url)
        }
    }

    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stop()
        }
    }
}
