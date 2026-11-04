import AVFoundation
import Combine
import SwiftUI

struct CompareSource: Identifiable, Equatable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    let kind: String
    let exportedAt: Date?
    let isReference: Bool

    init(
        url: URL,
        name: String,
        kind: String,
        exportedAt: Date?,
        isReference: Bool
    ) {
        self.url = url
        self.name = name
        self.kind = kind
        self.exportedAt = exportedAt
        self.isReference = isReference
    }
}

@MainActor
final class ComparisonAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var activeSource: CompareSource?
    @Published private(set) var previousSource: CompareSource?
    @Published var volume: Float = 1.0 {
        didSet {
            updatePlayerVolume()
        }
    }
    @Published private(set) var appliedGainDB: Float = 0
    @Published private(set) var isLoading: Bool = false
    @Published var playbackError: String?
    @Published var gainMatch: Bool = true
    @Published var sectionMode: Bool = false
    @Published var sources: [CompareSource] = []
    @Published var loudnessResults: [String: LoudnessResult] = [:]
    @Published var markers: [ComparisonMarker] = []

    let timeline = PlaybackTimeline()

    var onStartPlayback: (() -> Void)?

    private var player: AVAudioPlayer?
    private var prewarmedPlayers: [URL: AVAudioPlayer] = [:]
    private var timer: Timer?
    private var loopStart: TimeInterval?
    private var loopEnd: TimeInterval?
    private var preparationID = UUID()

    override init() {
        super.init()
    }

    var currentTime: TimeInterval { timeline.currentTime }
    var duration: TimeInterval { timeline.duration }
    var progress: Double { timeline.progress }

    // MARK: - Pre-warming

    func prewarm(sources: [CompareSource]) {
        self.sources = sources
        let urls = sources.map(\.url)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var loaded: [URL: AVAudioPlayer] = [:]
            for url in urls {
                if let p = try? AVAudioPlayer(contentsOf: url) {
                    p.prepareToPlay()
                    loaded[url] = p
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                for (url, p) in loaded {
                    if self.prewarmedPlayers[url] == nil {
                        self.prewarmedPlayers[url] = p
                    }
                }
            }
        }
    }

    // MARK: - A/B Switching & Playback

    func switchTo(
        _ source: CompareSource,
        allSources: [CompareSource],
        loudnessResults: [String: LoudnessResult],
        keepPosition: Bool = true,
        specifiedPosition: TimeInterval? = nil,
        sectionRange: ClosedRange<Double>? = nil,
        playImmediately: Bool? = nil
    ) {
        let wasPlaying = self.isPlaying
        let shouldPlay = playImmediately ?? wasPlaying

        let sourceDuration = audioDuration(source.url)
        let targetTime: TimeInterval
        if let specified = specifiedPosition {
            targetTime = specified
        } else if sectionMode, let range = sectionRange {
            targetTime = sourceDuration * range.lowerBound
        } else if keepPosition {
            targetTime = timeline.currentTime
        } else {
            targetTime = 0
        }

        let clampedTargetTime = min(max(0, targetTime), sourceDuration > 0 ? sourceDuration : 0)

        // Compute gain matching
        let targetLUFS = loudnessResults.values.map(\.integratedLUFS).min()
        let gain: Float
        if gainMatch, let current = loudnessResults[source.url.path], let targetLUFS {
            gain = Float(min(0, targetLUFS - current.integratedLUFS))
        } else {
            gain = 0
        }

        if let currentActive = activeSource, currentActive != source {
            previousSource = currentActive
        }
        activeSource = source
        appliedGainDB = gain

        // Stop current player cleanly
        stopTimer()
        player?.stop()
        player = nil

        let loopEndSeconds = (sectionMode && sectionRange != nil) ? (sourceDuration * sectionRange!.upperBound) : nil

        do {
            let prepared: AVAudioPlayer
            if let cached = prewarmedPlayers.removeValue(forKey: source.url) {
                prepared = cached
            } else {
                prepared = try AVAudioPlayer(contentsOf: source.url)
                prepared.prepareToPlay()
            }

            prepared.delegate = self
            self.appliedGainDB = min(0, gain)
            prepared.volume = self.volume * pow(10, self.appliedGainDB / 20)
            prepared.currentTime = min(clampedTargetTime, prepared.duration)
            self.loopStart = loopEndSeconds == nil ? nil : prepared.currentTime
            self.loopEnd = loopEndSeconds.map { min($0, prepared.duration) }
            self.player = prepared
            self.timeline.update(currentTime: prepared.currentTime, duration: prepared.duration)

            if shouldPlay {
                onStartPlayback?()
                if prepared.play() {
                    self.isPlaying = true
                    self.startTimer()
                } else {
                    self.playbackError = "Could not start audio playback."
                    self.isPlaying = false
                }
            } else {
                self.isPlaying = false
            }

            // Refill prewarm cache for this URL asynchronously
            let urlToPrewarm = source.url
            DispatchQueue.global(qos: .utility).async { [weak self] in
                if let refill = try? AVAudioPlayer(contentsOf: urlToPrewarm) {
                    refill.prepareToPlay()
                    DispatchQueue.main.async {
                        self?.prewarmedPlayers[urlToPrewarm] = refill
                    }
                }
            }
        } catch {
            self.playbackError = "Error loading \(source.name): \(error.localizedDescription)"
            self.isPlaying = false
        }
    }

    func toggleAB(
        allSources: [CompareSource],
        loudnessResults: [String: LoudnessResult],
        sectionRange: ClosedRange<Double>? = nil
    ) {
        guard !allSources.isEmpty else { return }

        if let prev = previousSource, prev != activeSource, allSources.contains(prev) {
            switchTo(
                prev,
                allSources: allSources,
                loudnessResults: loudnessResults,
                keepPosition: true,
                sectionRange: sectionRange
            )
            return
        }

        // Fallback: switch to next source
        switchNext(allSources: allSources, loudnessResults: loudnessResults, sectionRange: sectionRange)
    }

    func switchNext(
        allSources: [CompareSource],
        loudnessResults: [String: LoudnessResult],
        sectionRange: ClosedRange<Double>? = nil
    ) {
        guard !allSources.isEmpty else { return }
        guard let current = activeSource,
              let index = allSources.firstIndex(of: current) else {
            if let first = allSources.first {
                switchTo(first, allSources: allSources, loudnessResults: loudnessResults, keepPosition: true, sectionRange: sectionRange)
            }
            return
        }

        let nextIndex = (index + 1) % allSources.count
        switchTo(allSources[nextIndex], allSources: allSources, loudnessResults: loudnessResults, keepPosition: true, sectionRange: sectionRange)
    }

    func switchPrevious(
        allSources: [CompareSource],
        loudnessResults: [String: LoudnessResult],
        sectionRange: ClosedRange<Double>? = nil
    ) {
        guard !allSources.isEmpty else { return }
        guard let current = activeSource,
              let index = allSources.firstIndex(of: current) else {
            if let first = allSources.first {
                switchTo(first, allSources: allSources, loudnessResults: loudnessResults, keepPosition: true, sectionRange: sectionRange)
            }
            return
        }

        let prevIndex = (index - 1 + allSources.count) % allSources.count
        switchTo(allSources[prevIndex], allSources: allSources, loudnessResults: loudnessResults, keepPosition: true, sectionRange: sectionRange)
    }

    func togglePlayPause(
        allSources: [CompareSource] = [],
        loudnessResults: [String: LoudnessResult] = [:],
        sectionRange: ClosedRange<Double>? = nil
    ) {
        if let p = player {
            if p.isPlaying {
                p.pause()
                isPlaying = false
                stopTimer()
            } else {
                onStartPlayback?()
                p.play()
                isPlaying = true
                startTimer()
            }
        } else if let active = activeSource {
            switchTo(active, allSources: allSources, loudnessResults: loudnessResults, keepPosition: true, sectionRange: sectionRange, playImmediately: true)
        } else if let first = allSources.first {
            switchTo(first, allSources: allSources, loudnessResults: loudnessResults, keepPosition: false, sectionRange: sectionRange, playImmediately: true)
        }
    }

    func seek(to time: TimeInterval) {
        guard let p = player else { return }
        let target = min(max(0, time), p.duration)
        p.currentTime = target
        timeline.update(currentTime: target, duration: p.duration)
    }

    func seek(toFraction fraction: Double) {
        guard let p = player else { return }
        let target = min(max(0, fraction * p.duration), p.duration)
        p.currentTime = target
        timeline.update(currentTime: target, duration: p.duration)
    }

    func setVolume(_ newVolume: Float) {
        volume = min(max(0, newVolume), 1)
    }

    func switchTo(
        _ source: CompareSource,
        keepPosition: Bool = true,
        specifiedPosition: TimeInterval? = nil,
        sectionRange: ClosedRange<Double>? = nil,
        playImmediately: Bool? = nil
    ) {
        switchTo(
            source,
            allSources: self.sources.isEmpty ? [source] : self.sources,
            loudnessResults: self.loudnessResults,
            keepPosition: keepPosition,
            specifiedPosition: specifiedPosition,
            sectionRange: sectionRange,
            playImmediately: playImmediately
        )
    }

    func toggleAB(sectionRange: ClosedRange<Double>? = nil) {
        toggleAB(allSources: self.sources, loudnessResults: self.loudnessResults, sectionRange: sectionRange)
    }

    func switchNext(sectionRange: ClosedRange<Double>? = nil) {
        switchNext(allSources: self.sources, loudnessResults: self.loudnessResults, sectionRange: sectionRange)
    }

    func switchPrevious(sectionRange: ClosedRange<Double>? = nil) {
        switchPrevious(allSources: self.sources, loudnessResults: self.loudnessResults, sectionRange: sectionRange)
    }

    func togglePlayPause(sectionRange: ClosedRange<Double>? = nil) {
        togglePlayPause(allSources: self.sources, loudnessResults: self.loudnessResults, sectionRange: sectionRange)
    }

    func setGainMatch(_ enabled: Bool) {
        setGainMatch(enabled, loudnessResults: self.loudnessResults)
    }

    func setGainMatch(_ enabled: Bool, loudnessResults: [String: LoudnessResult]) {
        self.loudnessResults = loudnessResults
        gainMatch = enabled
        if let active = activeSource {
            let targetLUFS = loudnessResults.values.map(\.integratedLUFS).min()
            let gain: Float
            if gainMatch, let current = loudnessResults[active.url.path], let targetLUFS {
                gain = Float(min(0, targetLUFS - current.integratedLUFS))
            } else {
                gain = 0
            }
            appliedGainDB = gain
            updatePlayerVolume()
        }
    }

    func stop() {
        stopTimer()
        player?.stop()
        player = nil
        isPlaying = false
        timeline.reset()
        activeSource = nil
        previousSource = nil
        appliedGainDB = 0
        loopStart = nil
        loopEnd = nil
    }

    func pause() {
        guard let p = player, p.isPlaying else { return }
        p.pause()
        isPlaying = false
        stopTimer()
    }

    // MARK: - Helper Labels

    static func versionLetter(for index: Int) -> String {
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N"]
        if index < letters.count { return letters[index] }
        return "\(index + 1)"
    }

    func versionLetter(for source: CompareSource, in allSources: [CompareSource]) -> String {
        guard let idx = allSources.firstIndex(of: source) else { return "—" }
        return Self.versionLetter(for: idx)
    }

    // MARK: - Private details

    private func updatePlayerVolume() {
        guard let p = player else { return }
        p.volume = volume * pow(10, min(0, appliedGainDB) / 20)
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let p = self.player else { return }
                if let end = self.loopEnd, p.currentTime >= end {
                    p.currentTime = self.loopStart ?? 0
                }
                self.timeline.update(currentTime: p.currentTime, duration: p.duration)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func audioDuration(_ url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.stopTimer()
            self.timeline.update(currentTime: 0)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.isPlaying = false
            self.stopTimer()
            self.playbackError = error?.localizedDescription ?? "Playback decode error"
        }
    }
}
