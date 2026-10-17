import Foundation
import SwiftUI

enum CollectionColor: String, Codable, CaseIterable, Identifiable {
    case pink, purple, blue, cyan, green, yellow, orange

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .pink: return Color(hex: "FF3F9A")
        case .purple: return Color(hex: "9B5CFF")
        case .blue: return Color(hex: "357CFF")
        case .cyan: return Color(hex: "00B8C8")
        case .green: return Color(hex: "18B96B")
        case .yellow: return Color(hex: "E7AE00")
        case .orange: return Color(hex: "FF7A1A")
        }
    }
}

struct CollectionLegendItem: Identifiable, Equatable {
    let sourceURL: URL
    let color: CollectionColor

    var id: String { sourceURL.standardizedFileURL.path }
    var title: String { sourceURL.lastPathComponent }
}

@MainActor
final class CollectionColorStore: ObservableObject {
    @Published private(set) var assignments: [String: CollectionColor] = [:]
    @Published private(set) var emojis: [String: String] = [:]
    @Published private(set) var backgroundPaths: [String: String] = [:]
    @Published private(set) var stageSelections: [String: [Int]] = [:]
    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "collectionColors") {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([String: CollectionColor].self, from: data) {
            assignments = saved
        }
        emojis = defaults.dictionary(forKey: storageKey + ".emojis") as? [String: String] ?? [:]
        backgroundPaths = defaults.dictionary(forKey: storageKey + ".backgrounds") as? [String: String] ?? [:]
        if let data = defaults.data(forKey: storageKey + ".stages"),
           let saved = try? JSONDecoder().decode([String: [Int]].self, from: data) {
            stageSelections = saved
        }
    }

    func exactColor(for url: URL) -> CollectionColor? { assignments[url.path] }

    func resolvedColor(for url: URL) -> CollectionColor? {
        guard let sourceURL = resolvedColorSourceURL(for: url) else { return nil }
        return assignments[sourceURL.path]
    }

    func resolvedColorSourceURL(for url: URL) -> URL? {
        let path = url.standardizedFileURL.path
        let sourcePath = assignments
            .filter { path == $0.key || path.hasPrefix($0.key + "/") }
            .max { $0.key.count < $1.key.count }?
            .key
        guard let sourcePath else { return nil }
        return URL(fileURLWithPath: sourcePath)
    }

    func legendItems(for urls: [URL]) -> [CollectionLegendItem] {
        var itemsByPath: [String: CollectionLegendItem] = [:]
        for url in urls {
            guard let sourceURL = resolvedColorSourceURL(for: url),
                  let color = assignments[sourceURL.path] else { continue }
            let item = CollectionLegendItem(sourceURL: sourceURL, color: color)
            itemsByPath[item.id] = item
        }
        return itemsByPath.values.sorted {
            let titleOrder = $0.title.localizedStandardCompare($1.title)
            return titleOrder == .orderedSame ? $0.id < $1.id : titleOrder == .orderedAscending
        }
    }

    func setColor(_ color: CollectionColor?, for url: URL) {
        if let color { assignments[url.path] = color }
        else { assignments.removeValue(forKey: url.path) }
        guard let data = try? JSONEncoder().encode(assignments) else { return }
        defaults.set(data, forKey: storageKey)
    }

    func exactEmoji(for url: URL) -> String? { emojis[url.path] }

    func resolvedEmoji(for url: URL) -> String? { resolvedValue(in: emojis, for: url) }

    func setEmoji(_ value: String?, for url: URL) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let first = trimmed.first { emojis[url.path] = String(first) }
        else { emojis.removeValue(forKey: url.path) }
        defaults.set(emojis, forKey: storageKey + ".emojis")
    }

    func resolvedBackgroundURL(for url: URL) -> URL? {
        guard let path = resolvedValue(in: backgroundPaths, for: url),
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    func setBackgroundURL(_ imageURL: URL?, for url: URL) {
        if let imageURL { backgroundPaths[url.path] = imageURL.path }
        else { backgroundPaths.removeValue(forKey: url.path) }
        defaults.set(backgroundPaths, forKey: storageKey + ".backgrounds")
    }

    func exactAllowedStages(for url: URL) -> [ProjectStage]? {
        stageSelections[url.path]?.compactMap(ProjectStage.init(rawValue:))
            .sorted { $0.workflowIndex < $1.workflowIndex }
    }

    func allowedStages(for url: URL) -> [ProjectStage] {
        guard let rawValues: [Int] = resolvedValue(in: stageSelections, for: url) else {
            return ProjectStage.allCases
        }
        let stages = rawValues.compactMap(ProjectStage.init(rawValue:))
            .sorted { $0.workflowIndex < $1.workflowIndex }
        return stages.isEmpty ? ProjectStage.allCases : stages
    }

    func setStage(_ stage: ProjectStage, enabled: Bool, for url: URL) {
        var stages = exactAllowedStages(for: url) ?? allowedStages(for: url)
        if enabled, !stages.contains(stage) { stages.append(stage) }
        if !enabled, stages.count > 1 { stages.removeAll { $0 == stage } }
        stageSelections[url.path] = stages.map(\.rawValue)
        if let data = try? JSONEncoder().encode(stageSelections) {
            defaults.set(data, forKey: storageKey + ".stages")
        }
    }

    func resetStages(for url: URL) {
        stageSelections.removeValue(forKey: url.path)
        if let data = try? JSONEncoder().encode(stageSelections) {
            defaults.set(data, forKey: storageKey + ".stages")
        }
    }

    private func resolvedValue<T>(in values: [String: T], for url: URL) -> T? {
        let path = url.standardizedFileURL.path
        return values
            .filter { path == $0.key || path.hasPrefix($0.key + "/") }
            .max { $0.key.count < $1.key.count }?
            .value
    }
}
