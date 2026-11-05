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

struct ChannelLevels: Equatable {
    var livePeakL: Float = -60.0
    var livePeakR: Float = -60.0
    var rmsL: Float = -60.0
    var rmsR: Float = -60.0
    var maxPeakL: Float = -60.0
    var maxPeakR: Float = -60.0
    var maxRMSL: Float = -60.0
    var maxRMSR: Float = -60.0
}

@MainActor
final class ComparisonAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var activeSource: CompareSource?
    @Published private(set) var previousSource: CompareSource?
    @Published var meterSourceA: CompareSource?
    @Published var meterSourceB: CompareSource?
    @Published var trackLevels: [String: ChannelLevels] = [:]
    @Published var isMonoMonitoring: Bool = false
    @Published var volume: Float = 1.0 {
        didSet {
            updatePlayerVolume()
        }
    }
    @Published var trackGainDB: [String: Float] = [:] {
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
        if meterSourceA == nil, let first = sources.first {
            meterSourceA = first
        }
        if meterSourceB == nil, let second = sources.dropFirst().first {
            meterSourceB = second
        }
        let urls = sources.map(\.url)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var loaded: [URL: AVAudioPlayer] = [:]
            for url in urls {
                if let p = try? AVAudioPlayer(contentsOf: url) {
                    p.isMeteringEnabled = true
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

        // Compute gain matching or individual track gain
        let gain: Float
        if let customGain = trackGainDB[source.url.path] {
            gain = customGain
        } else if gainMatch, let current = loudnessResults[source.url.path],
                  let targetLUFS = loudnessResults.values.map(\.integratedLUFS).min() {
            gain = Float(min(0, targetLUFS - current.integratedLUFS))
            trackGainDB[source.url.path] = gain
        } else {
            gain = 0
        }

        if let currentActive = activeSource, currentActive != source {
            previousSource = currentActive
        }

        // Maintain the last two selected tracks in Slot A and Slot B
        if meterSourceA == nil {
            meterSourceA = source
        } else if meterSourceB == nil && source != meterSourceA {
            meterSourceB = source
        } else if source != meterSourceA && source != meterSourceB {
            if let currentActive = activeSource, currentActive == meterSourceA {
                meterSourceB = source
            } else {
                meterSourceA = source
            }
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
                prepared.isMeteringEnabled = true
                prepared.prepareToPlay()
            }

            prepared.isMeteringEnabled = true
            prepared.delegate = self
            self.appliedGainDB = gain
            let linearMultiplier = pow(10.0, gain / 20.0)
            prepared.volume = min(max(0.0, self.volume * linearMultiplier), 2.0)
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
                    refill.isMeteringEnabled = true
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

    func gainDB(for sourcePath: String) -> Float {
        trackGainDB[sourcePath] ?? 0.0
    }

    func setGainDB(_ gain: Float, for sourcePath: String) {
        trackGainDB[sourcePath] = gain
        if activeSource?.url.path == sourcePath {
            appliedGainDB = gain
            updatePlayerVolume()
        }
    }

    func resetGain(for sourcePath: String) {
        setGainDB(0.0, for: sourcePath)
    }

    func resetAllGains(for sources: [CompareSource] = []) {
        if sources.isEmpty {
            trackGainDB.removeAll()
        } else {
            for s in sources {
                trackGainDB[s.url.path] = 0.0
            }
        }
        if let active = activeSource {
            appliedGainDB = trackGainDB[active.url.path] ?? 0.0
        }
        updatePlayerVolume()
    }

    func applyGainMatch(with loudnessResults: [String: LoudnessResult], sources: [CompareSource]) {
        self.loudnessResults = loudnessResults
        let allLUFS = sources.compactMap { loudnessResults[$0.url.path]?.integratedLUFS }
        guard let targetLUFS = allLUFS.min() else { return }

        for source in sources {
            if let current = loudnessResults[source.url.path]?.integratedLUFS {
                let diff = Float(targetLUFS - current)
                trackGainDB[source.url.path] = diff
            }
        }
        gainMatch = true
        if let active = activeSource {
            appliedGainDB = trackGainDB[active.url.path] ?? 0.0
        }
        updatePlayerVolume()
    }

    func setGainMatch(_ enabled: Bool) {
        setGainMatch(enabled, loudnessResults: self.loudnessResults)
    }

    func setGainMatch(_ enabled: Bool, loudnessResults: [String: LoudnessResult]) {
        self.loudnessResults = loudnessResults
        gainMatch = enabled
        if enabled {
            applyGainMatch(with: loudnessResults, sources: self.sources)
        } else {
            resetAllGains(for: self.sources)
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
        let currentTrackGain = activeSource.flatMap { trackGainDB[$0.url.path] } ?? appliedGainDB
        let linearMultiplier = pow(10.0, currentTrackGain / 20.0)
        p.volume = min(max(0.0, volume * linearMultiplier), 2.0)
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
                self.updateMeters()
            }
        }
    }

    func levels(for source: CompareSource?) -> ChannelLevels {
        guard let source else { return ChannelLevels() }
        if let existing = trackLevels[source.url.path] {
            return existing
        }
        if let loudness = loudnessResults[source.url.path] {
            let gain = gainDB(for: source.url.path)
            let peak = Float(loudness.samplePeakDBFS) + gain
            let rms = Float(loudness.integratedLUFS) + gain
            return ChannelLevels(
                livePeakL: peak,
                livePeakR: peak,
                rmsL: rms,
                rmsR: rms,
                maxPeakL: peak,
                maxPeakR: peak,
                maxRMSL: rms,
                maxRMSR: rms
            )
        }
        return ChannelLevels()
    }

    func resetMeterPeaks() {
        for key in trackLevels.keys {
            var lvl = trackLevels[key] ?? ChannelLevels()
            lvl.maxPeakL = -60.0
            lvl.maxPeakR = -60.0
            lvl.maxRMSL = -60.0
            lvl.maxRMSR = -60.0
            trackLevels[key] = lvl
        }
    }

    private func updateMeters() {
        guard let p = player, let active = activeSource else { return }
        p.updateMeters()

        let numChannels = p.numberOfChannels
        let rawAvg0 = p.averagePower(forChannel: 0)
        let rawPeak0 = p.peakPower(forChannel: 0)
        let rawAvg1 = numChannels > 1 ? p.averagePower(forChannel: 1) : rawAvg0
        let rawPeak1 = numChannels > 1 ? p.peakPower(forChannel: 1) : rawPeak0

        let gain = trackGainDB[active.url.path] ?? appliedGainDB

        let currentAvgL = isMonoMonitoring ? max(-60.0, ((rawAvg0 + rawAvg1) / 2) + gain) : max(-60.0, rawAvg0 + gain)
        let currentAvgR = isMonoMonitoring ? currentAvgL : max(-60.0, rawAvg1 + gain)
        let currentPeakL = isMonoMonitoring ? max(-60.0, max(rawPeak0, rawPeak1) + gain) : max(-60.0, rawPeak0 + gain)
        let currentPeakR = isMonoMonitoring ? currentPeakL : max(-60.0, rawPeak1 + gain)

        var existing = trackLevels[active.url.path] ?? ChannelLevels()

        // Ballistics:
        // Smooth RMS
        if currentAvgL > existing.rmsL {
            existing.rmsL = existing.rmsL * 0.35 + currentAvgL * 0.65
        } else {
            existing.rmsL = max(-60.0, existing.rmsL - 1.2)
        }

        if currentAvgR > existing.rmsR {
            existing.rmsR = existing.rmsR * 0.35 + currentAvgR * 0.65
        } else {
            existing.rmsR = max(-60.0, existing.rmsR - 1.2)
        }

        // Live Peak
        if currentPeakL > existing.livePeakL {
            existing.livePeakL = currentPeakL
        } else {
            existing.livePeakL = max(-60.0, existing.livePeakL - 0.7)
        }

        if currentPeakR > existing.livePeakR {
            existing.livePeakR = currentPeakR
        } else {
            existing.livePeakR = max(-60.0, existing.livePeakR - 0.7)
        }

        // Peak Hold
        if currentPeakL > existing.maxPeakL {
            existing.maxPeakL = currentPeakL
        }
        if currentPeakR > existing.maxPeakR {
            existing.maxPeakR = currentPeakR
        }
        if currentAvgL > existing.maxRMSL {
            existing.maxRMSL = currentAvgL
        }
        if currentAvgR > existing.maxRMSR {
            existing.maxRMSR = currentAvgR
        }

        trackLevels[active.url.path] = existing
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
