import Foundation
import AVFoundation

public struct WaveformSectionMarker: Identifiable, Equatable, Sendable {
    public let id: String
    public let fraction: Double
    public let title: String
    public let note: String
    public let isAbletonLocator: Bool

    public init(
        id: String = UUID().uuidString,
        fraction: Double,
        title: String,
        note: String = "",
        isAbletonLocator: Bool = false
    ) {
        self.id = id
        self.fraction = min(max(fraction, 0.0), 1.0)
        self.title = title
        self.note = note
        self.isAbletonLocator = isAbletonLocator
    }
}

enum WaveformMarkerResolver {
    private static var locatorCache: [URL: (Date, [AbletonLocator])] = [:]
    private static let lock = NSLock()

    @MainActor
    static func resolveMarkers(
        for trackURL: URL,
        duration: Double,
        project: Project?,
        comparisonMarkers: ComparisonMarkerStore?
    ) async -> [WaveformSectionMarker] {
        let actualDuration = duration > 0 ? duration : audioDuration(for: trackURL)
        guard actualDuration > 0 else { return [] }

        // 1. If project has explicit comparison markers for this track, use them
        if let project, let comparisonMarkers {
            let markers = comparisonMarkers.markers(for: project)
            let matching = markers.compactMap { m -> WaveformSectionMarker? in
                guard let fraction = m.position(
                    for: trackURL.path,
                    legacySourcePath: project.sortedTracks.first?.url.path
                ) else {
                    return nil
                }
                return WaveformSectionMarker(
                    id: m.id.uuidString,
                    fraction: fraction,
                    title: m.title,
                    note: m.note,
                    isAbletonLocator: m.origin == .ableton
                )
            }
            if !matching.isEmpty {
                return matching.sorted { $0.fraction < $1.fraction }
            }
        }

        // 2. Otherwise, automatically derive from the project's newest Ableton set (.als) locators
        guard let project,
              let alsURL = project.newestAbletonVersion?.url,
              let bpm = project.bpm,
              bpm > 0 else {
            return []
        }

        let locators = await Task.detached(priority: .utility) {
            readCachedLocators(from: alsURL)
        }.value

        return locators.compactMap { locator -> WaveformSectionMarker? in
            let seconds = locator.timeInBeats * (60.0 / bpm)
            let fraction = seconds / actualDuration
            guard fraction >= 0.0 && fraction <= 1.0 else { return nil }
            return WaveformSectionMarker(
                id: "\(locator.timeInBeats)-\(locator.name)",
                fraction: fraction,
                title: locator.name,
                note: locator.annotation,
                isAbletonLocator: true
            )
        }
        .sorted { $0.fraction < $1.fraction }
    }

    public static func audioDuration(for url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    private static func readCachedLocators(from url: URL) -> [AbletonLocator] {
        let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        lock.lock()
        if let cached = locatorCache[url], cached.0 == modDate {
            lock.unlock()
            return cached.1
        }
        lock.unlock()

        let parsed = AbletonProjectInspector.readLocators(from: url)
        lock.lock()
        locatorCache[url] = (modDate, parsed)
        lock.unlock()
        return parsed
    }
}
