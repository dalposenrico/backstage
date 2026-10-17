import Foundation
import SwiftUI

enum ProjectStage: Int, Codable, CaseIterable {
    case spark = 1, structure, fullTrack, mix, done
    // Appended so legacy raw value 5 continues to decode as Done.
    case master = 6

    static let allCases: [ProjectStage] = [.spark, .structure, .fullTrack, .mix, .master, .done]

    var workflowIndex: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    var next: ProjectStage? {
        let nextIndex = workflowIndex + 1
        return Self.allCases.indices.contains(nextIndex) ? Self.allCases[nextIndex] : nil
    }

    var title: String {
        switch self {
        case .spark: return "Idea / Loop"
        case .structure: return "Structure"
        case .fullTrack: return "Full Track"
        case .mix: return "Mix"
        case .master: return "Master"
        case .done: return "Done"
        }
    }
}

struct ProjectProgress: Codable {
    var stage: ProjectStage = .spark
    var nextMove = ""
    var sparkRating = 0
    var isFocused = false
    var stageChangedAt = Date()
}

enum ProjectDirection {
    case mustFinish, explore, easyWin, needsDirection, probablyPark, resting, unrated

    var title: String {
        switch self {
        case .mustFinish: return "Must Finish"
        case .explore: return "Explore"
        case .easyWin: return "Easy Win"
        case .needsDirection: return "Needs Direction"
        case .probablyPark: return "Probably Park"
        case .resting: return "Resting"
        case .unrated: return "Rate It"
        }
    }

    var icon: String {
        switch self {
        case .mustFinish: return "flame.fill"
        case .explore: return "sparkles"
        case .easyWin: return "flag.checkered"
        case .needsDirection: return "arrow.triangle.branch"
        case .probablyPark: return "pause.fill"
        case .resting: return "moon.fill"
        case .unrated: return "questionmark"
        }
    }

    var color: Color {
        switch self {
        case .mustFinish: return Color(hex: "EE4F9B")
        case .explore: return Color(hex: "8759E8")
        case .easyWin: return Color(hex: "25A866")
        case .needsDirection: return Color(hex: "D58A16")
        case .probablyPark: return Color(hex: "76808F")
        case .resting: return Color(hex: "4C78A8")
        case .unrated: return Color.tertiaryText
        }
    }

    static func evaluate(project: Project, progress: ProjectProgress, now: Date = Date()) -> ProjectDirection {
        guard progress.sparkRating > 0 else { return .unrated }
        let stage = progress.stage.workflowIndex
        let fullTrack = ProjectStage.fullTrack.workflowIndex
        let mix = ProjectStage.mix.workflowIndex

        if progress.sparkRating >= 4 && stage >= fullTrack { return .mustFinish }
        if progress.sparkRating >= 4 { return .explore }
        if stage >= mix && progress.sparkRating >= 2 { return .easyWin }
        if progress.sparkRating >= 3 && progress.nextMove.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .needsDirection
        }
        if progress.sparkRating <= 2 && stage < fullTrack { return .probablyPark }
        if project.latestModification != .distantPast && now.timeIntervalSince(project.latestModification) > 45 * 86_400 {
            return .resting
        }
        return progress.sparkRating >= 3 ? .explore : .probablyPark
    }

    func explanation(project: Project, progress: ProjectProgress) -> String {
        switch self {
        case .mustFinish:
            return "High excitement (\(progress.sparkRating)/5) and already at \(progress.stage.title)—protect time to finish it."
        case .explore:
            return "High excitement (\(progress.sparkRating)/5) while the track is still at \(progress.stage.title)—explore the idea further."
        case .easyWin:
            return "Already at \(progress.stage.title) with enough excitement to make finishing worthwhile."
        case .needsDirection:
            return "Promising excitement (\(progress.sparkRating)/5), but it has no concrete next move yet."
        case .probablyPark:
            return "Low excitement (\(progress.sparkRating)/5) at the \(progress.stage.title) stage—consider parking it without guilt."
        case .resting:
            return "This track has been quiet for a while; revisit it when it feels useful again."
        case .unrated:
            return "Add an excitement rating to receive an automatic direction suggestion."
        }
    }
}

@MainActor
final class ProjectProgressStore: ObservableObject {
    @Published private var values: [String: ProjectProgress] = [:]
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("Backstage", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("project-progress.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([String: ProjectProgress].self, from: data) {
            values = saved
        }
    }

    func progress(for project: Project) -> ProjectProgress {
        values[project.folderURL.path] ?? ProjectProgress()
    }


    func setStage(_ stage: ProjectStage, for project: Project) {
        update(project) { value in
            if value.stage != stage { value.stageChangedAt = Date() }
            value.stage = stage
        }
    }

    func nextMoveBinding(for project: Project) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.progress(for: project).nextMove ?? "" },
            set: { [weak self] text in self?.update(project) { $0.nextMove = text } }
        )
    }

    func setSparkRating(_ rating: Int, for project: Project) {
        update(project) { $0.sparkRating = max(0, min(5, rating)) }
    }

    private func update(_ project: Project, change: (inout ProjectProgress) -> Void) {
        var value = progress(for: project)
        change(&value)
        values[project.folderURL.path] = value
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(values) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
