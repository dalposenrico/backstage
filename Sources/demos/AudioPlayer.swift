import AVFoundation
import Combine

class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var currentTrack: Track?
    @Published var volume: Float = 1.0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    var progress: Double {
        duration > 0 ? currentTime / duration : 0
    }

    func play(_ track: Track) {
        stop()
        do {
            let p = try AVAudioPlayer(contentsOf: track.url)
            p.delegate = self
            p.volume = volume
            p.prepareToPlay()
            p.play()
            player = p
            isPlaying = true
            currentTrack = track
            duration = p.duration
            currentTime = 0
            startTimer()
        } catch {
            print("AudioPlayer: \(error.localizedDescription)")
        }
    }

    func togglePlayPause() {
        guard let p = player else { return }
        if p.isPlaying {
            p.pause()
            isPlaying = false
            stopTimer()
        } else {
            p.play()
            isPlaying = true
            startTimer()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        currentTrack = nil
        stopTimer()
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    func setVolume(_ v: Float) {
        volume = v
        player?.volume = v
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.currentTime = self?.player?.currentTime ?? 0
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentTime = self.duration
            self.stopTimer()
        }
    }
}
