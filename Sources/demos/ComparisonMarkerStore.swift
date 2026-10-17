import Foundation

enum ComparisonMarkerOrigin: String, Codable, Sendable {
    case manual
    case ableton
}

enum ComparisonItemKind: String, Codable, Sendable {
    case marker
    case section
}

enum ComparisonBeatGrid {
    static func snappedFraction(_ fraction: Double, duration: Double, bpm: Double) -> Double {
        guard duration > 0, bpm > 0 else { return min(max(fraction, 0), 1) }
        let beatDuration = 60 / bpm
        let snappedSeconds = (min(max(fraction, 0), 1) * duration / beatDuration).rounded() * beatDuration
        return min(max(snappedSeconds / duration, 0), 1)
    }

    static func visibleIntervalInBeats(duration: Double, bpm: Double, width: Double) -> Double {
        guard duration > 0, bpm > 0, width > 0 else { return 4 }
        let beatWidth = width / (duration * bpm / 60)
        if beatWidth >= 7 { return 1 }
        if beatWidth * 4 >= 7 { return 4 }
        return 16
    }
}

struct ComparisonMarker: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    // Kept for decoding markers saved before per-version placement existed and
    // as a stable sort position for a section.
    var fraction: Double
    var sourceFractions: [String: Double]
    var sourceEndFractions: [String: Double]
    var title: String
    var note: String
    var preferredSourcePaths: [String]
    let kind: ComparisonItemKind
    let origin: ComparisonMarkerOrigin

    init(
        id: UUID = UUID(),
        fraction: Double,
        sourceFractions: [String: Double] = [:],
        sourceEndFractions: [String: Double] = [:],
        title: String,
        note: String = "",
        preferredSourcePaths: [String] = [],
        kind: ComparisonItemKind = .marker,
        origin: ComparisonMarkerOrigin = .manual
    ) {
        self.id = id
        self.fraction = min(max(fraction, 0), 1)
        self.sourceFractions = sourceFractions.mapValues { min(max($0, 0), 1) }
        self.sourceEndFractions = sourceEndFractions.mapValues { min(max($0, 0), 1) }
        self.title = title
        self.note = note
        self.preferredSourcePaths = preferredSourcePaths
        self.kind = kind
        self.origin = origin
    }

    func position(for sourcePath: String, legacySourcePath: String?) -> Double? {
        if let position = sourceFractions[sourcePath] { return position }
        // Old markers used one shared percentage. Show that position only on
        // the newest export instead of pretending every arrangement aligns.
        if sourceFractions.isEmpty, sourcePath == legacySourcePath { return fraction }
        return nil
    }

    func range(for sourcePath: String, legacySourcePath: String?) -> ClosedRange<Double>? {
        guard kind == .section else { return nil }
        guard let start = position(for: sourcePath, legacySourcePath: legacySourcePath) else { return nil }
        let end = max(start + 0.01, sourceEndFractions[sourcePath] ?? min(start + 0.08, 1))
        return start...min(end, 1)
    }

    mutating func setPosition(_ position: Double, for sourcePath: String) {
        let clamped = min(max(position, 0), 1)
        if kind == .marker {
            sourceFractions[sourcePath] = clamped
            sourceEndFractions.removeValue(forKey: sourcePath)
            fraction = sourceFractions.values.min() ?? clamped
            return
        }
        let existingLength = max(
            0.01,
            (sourceEndFractions[sourcePath] ?? clamped + 0.08) - (sourceFractions[sourcePath] ?? clamped)
        )
        sourceFractions[sourcePath] = clamped
        sourceEndFractions[sourcePath] = min(clamped + existingLength, 1)
        fraction = sourceFractions.values.min() ?? clamped
    }

    mutating func setRange(start: Double, end: Double, for sourcePath: String) {
        let clampedStart = min(max(start, 0), 0.99)
        sourceFractions[sourcePath] = clampedStart
        sourceEndFractions[sourcePath] = min(max(end, clampedStart + 0.01), 1)
        fraction = sourceFractions.values.min() ?? clampedStart
    }

    private enum CodingKeys: String, CodingKey {
        case id, fraction, sourceFractions, sourceEndFractions, title, note, preferredSourcePaths, kind, origin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fraction = min(max(try container.decode(Double.self, forKey: .fraction), 0), 1)
        sourceFractions = try container.decodeIfPresent([String: Double].self, forKey: .sourceFractions) ?? [:]
        sourceFractions = sourceFractions.mapValues { min(max($0, 0), 1) }
        sourceEndFractions = try container.decodeIfPresent([String: Double].self, forKey: .sourceEndFractions) ?? [:]
        sourceEndFractions = sourceEndFractions.mapValues { min(max($0, 0), 1) }
        title = try container.decode(String.self, forKey: .title)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        preferredSourcePaths = try container.decodeIfPresent([String].self, forKey: .preferredSourcePaths) ?? []
        kind = try container.decodeIfPresent(ComparisonItemKind.self, forKey: .kind)
            ?? (sourceEndFractions.isEmpty ? .marker : .section)
        origin = try container.decodeIfPresent(ComparisonMarkerOrigin.self, forKey: .origin) ?? .manual
    }
}

struct ComparisonAssemblyItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let markerID: UUID
    let sourcePath: String

    init(id: UUID = UUID(), markerID: UUID, sourcePath: String) {
        self.id = id
        self.markerID = markerID
        self.sourcePath = sourcePath
    }
}

private struct ComparisonWorkspaceData: Codable {
    var markersByProject: [String: [ComparisonMarker]]
    var assemblyByProject: [String: [ComparisonAssemblyItem]]
}

@MainActor
final class ComparisonMarkerStore: ObservableObject {
    @Published private var markersByProject: [String: [ComparisonMarker]] = [:]
    @Published private var assemblyByProject: [String: [ComparisonAssemblyItem]] = [:]
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let directory = support.appendingPathComponent("Backstage", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("comparison-markers.json")
        }
        if let data = try? Data(contentsOf: self.fileURL) {
            if let saved = try? JSONDecoder().decode(ComparisonWorkspaceData.self, from: data) {
                markersByProject = saved.markersByProject
                assemblyByProject = saved.assemblyByProject
            } else if let legacy = try? JSONDecoder().decode([String: [ComparisonMarker]].self, from: data) {
                markersByProject = legacy
            }
        }
    }

    func markers(for project: Project) -> [ComparisonMarker] {
        (markersByProject[project.folderURL.path] ?? []).sorted { $0.fraction < $1.fraction }
    }

    @discardableResult
    func add(
        to project: Project,
        at fraction: Double,
        sourcePath: String? = nil,
        title: String = "New marker",
        note: String = "",
        kind: ComparisonItemKind = .marker,
        origin: ComparisonMarkerOrigin = .manual
    ) -> ComparisonMarker {
        let marker = ComparisonMarker(
            fraction: fraction,
            sourceFractions: sourcePath.map { [$0: fraction] } ?? [:],
            sourceEndFractions: kind == .section
                ? sourcePath.map { [$0: min(fraction + 0.08, 1)] } ?? [:]
                : [:],
            title: title,
            note: note,
            kind: kind,
            origin: origin
        )
        markersByProject[project.folderURL.path, default: []].append(marker)
        save()
        return marker
    }

    func update(_ marker: ComparisonMarker, for project: Project) {
        guard let index = markersByProject[project.folderURL.path]?.firstIndex(where: { $0.id == marker.id }) else { return }
        markersByProject[project.folderURL.path]?[index] = marker
        save()
    }

    func remove(_ marker: ComparisonMarker, from project: Project) {
        markersByProject[project.folderURL.path]?.removeAll { $0.id == marker.id }
        assemblyByProject[project.folderURL.path]?.removeAll { $0.markerID == marker.id }
        save()
    }

    func assembly(for project: Project) -> [ComparisonAssemblyItem] {
        assemblyByProject[project.folderURL.path] ?? []
    }

    func addToAssembly(_ marker: ComparisonMarker, sourcePath: String, for project: Project) {
        guard marker.kind == .section else { return }
        assemblyByProject[project.folderURL.path, default: []].append(
            ComparisonAssemblyItem(markerID: marker.id, sourcePath: sourcePath)
        )
        save()
    }

    func removeFromAssembly(_ item: ComparisonAssemblyItem, for project: Project) {
        assemblyByProject[project.folderURL.path]?.removeAll { $0.id == item.id }
        save()
    }

    func moveAssemblyItem(_ item: ComparisonAssemblyItem, by offset: Int, for project: Project) {
        guard var items = assemblyByProject[project.folderURL.path],
              let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let destination = min(max(index + offset, 0), items.count - 1)
        guard destination != index else { return }
        let moved = items.remove(at: index)
        items.insert(moved, at: destination)
        assemblyByProject[project.folderURL.path] = items
        save()
    }

    func importAbleton(
        _ candidates: [(fraction: Double, locator: AbletonLocator)],
        into project: Project,
        sourcePath: String? = nil
    ) -> Int {
        var existing = markersByProject[project.folderURL.path] ?? []
        var added = 0
        for candidate in candidates {
            let duplicate = existing.contains {
                $0.origin == .ableton
                    && $0.title.caseInsensitiveCompare(candidate.locator.name) == .orderedSame
                    && abs($0.fraction - candidate.fraction) < 0.002
            }
            guard !duplicate else { continue }
            existing.append(ComparisonMarker(
                fraction: candidate.fraction,
                sourceFractions: sourcePath.map { [$0: candidate.fraction] } ?? [:],
                title: candidate.locator.name,
                note: candidate.locator.annotation,
                kind: .marker,
                origin: .ableton
            ))
            added += 1
        }
        markersByProject[project.folderURL.path] = existing
        if added > 0 { save() }
        return added
    }

    private func save() {
        let workspace = ComparisonWorkspaceData(
            markersByProject: markersByProject,
            assemblyByProject: assemblyByProject
        )
        guard let data = try? JSONEncoder().encode(workspace) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
