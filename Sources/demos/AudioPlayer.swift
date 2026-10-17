import AVFoundation
import Combine

/// High-frequency playback position updates live separately from the player's
/// low-frequency state so a ticking seek bar does not invalidate the library UI.
final class PlaybackTimeline: ObservableObject {
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    var progress: Double {
        duration > 0 ? currentTime / duration : 0
    }

    fileprivate func update(currentTime: TimeInterval, duration: TimeInterval? = nil) {
        self.currentTime = currentTime
        if let duration { self.duration = duration }
    }

    fileprivate func reset() {
        currentTime = 0
        duration = 0
    }
}

class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var currentTrack: Track?
    @Published var volume: Float = 1.0
    @Published var appliedGainDB: Float = 0
    @Published var isLoading = false
    @Published var playbackError: String?

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var loopStart: TimeInterval?
    private var loopEnd: TimeInterval?
    private var preparationID = UUID()
    let timeline = PlaybackTimeline()

    var currentTime: TimeInterval { timeline.currentTime }
    var duration: TimeInterval { timeline.duration }

    var progress: Double {
        timeline.progress
    }

    func play(_ track: Track, startAt: TimeInterval = 0, gainDB: Float = 0, loopEnd: TimeInterval? = nil) {
        stop()
        let requestID = UUID()
        preparationID = requestID
        isLoading = true
        playbackError = nil
        currentTrack = track
        AccountDiagnostics.record("Local playback preparation started; type=\(track.fileExtension)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let preparedPlayer = try AVAudioPlayer(contentsOf: track.url)
                let prepared = preparedPlayer.prepareToPlay()
                DispatchQueue.main.async {
                    guard let self, self.preparationID == requestID else {
                        preparedPlayer.stop()
                        return
                    }
                    guard prepared else {
                        self.finishLoadingWithError("This audio file could not be prepared for playback.")
                        return
                    }
                    preparedPlayer.delegate = self
                    self.appliedGainDB = min(0, gainDB)
                    preparedPlayer.volume = self.volume * pow(10, self.appliedGainDB / 20)
                    preparedPlayer.currentTime = min(max(0, startAt), preparedPlayer.duration)
                    self.loopStart = loopEnd == nil ? nil : preparedPlayer.currentTime
                    self.loopEnd = loopEnd.map { min($0, preparedPlayer.duration) }
                    self.player = preparedPlayer
                    self.timeline.update(
                        currentTime: preparedPlayer.currentTime,
                        duration: preparedPlayer.duration
                    )
                    self.isLoading = false
                    if preparedPlayer.play() {
                        self.isPlaying = true
                        self.startTimer()
                        AccountDiagnostics.record("Local playback started after background preparation")
                    } else {
                        self.finishLoadingWithError("macOS could not start this audio file.")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self, self.preparationID == requestID else { return }
                    self.finishLoadingWithError("Couldn’t open this audio file: \(error.localizedDescription)")
                }
            }
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
        preparationID = UUID()
        player?.stop()
        player = nil
        isPlaying = false
        timeline.reset()
        currentTrack = nil
        isLoading = false
        appliedGainDB = 0
        loopStart = nil
        loopEnd = nil
        stopTimer()
    }

    private func finishLoadingWithError(_ message: String) {
        isLoading = false
        isPlaying = false
        playbackError = message
        AccountDiagnostics.record("Local playback failed: \(message)")
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        timeline.update(currentTime: time)
    }

    func setVolume(_ v: Float) {
        volume = v
        player?.volume = v * pow(10, appliedGainDB / 20)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let end = self.loopEnd, let start = self.loopStart, (self.player?.currentTime ?? 0) >= end {
                self.player?.currentTime = start
            }
            self.timeline.update(currentTime: self.player?.currentTime ?? 0)
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
            self.timeline.update(currentTime: self.duration)
            self.stopTimer()
        }
    }
}
