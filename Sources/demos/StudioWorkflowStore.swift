import Foundation
import SwiftUI

@MainActor
final class StudioWorkflowStore: ObservableObject {
    @Published private(set) var customization: StudioWorkflowCustomization
    @Published private(set) var projectStates: [String: ProjectWorkflowState]

    let builtInItems: [StudioWorkflowItem]
    private let templateURL: URL
    private let projectsURL: URL

    init(supportDirectory: URL? = nil, builtInItems: [StudioWorkflowItem] = BuiltInStudioWorkflow.items) {
        self.builtInItems = builtInItems
        let directory = supportDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Backstage", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        templateURL = directory.appendingPathComponent("studio-workflow-template.json")
        projectsURL = directory.appendingPathComponent("project-workflows.json")
        customization = Self.load(StudioWorkflowCustomization.self, from: templateURL) ?? StudioWorkflowCustomization()
        projectStates = Self.load([String: ProjectWorkflowState].self, from: projectsURL) ?? [:]
    }

    var items: [StudioWorkflowItem] {
        StudioWorkflowResolver.resolve(defaults: builtInItems, customization: customization)
    }

    func items(for stage: ProjectStage) -> [StudioWorkflowItem] { items.filter { $0.stage == stage } }
    func hiddenBuiltIns(for stage: ProjectStage) -> [StudioWorkflowItem] {
        builtInItems.filter { $0.stage == stage && customization.hiddenBuiltInIDs.contains($0.id) }
            .sorted(by: StudioWorkflowResolver.sortItems)
    }
    func isBuiltIn(_ item: StudioWorkflowItem) -> Bool { builtInItems.contains { $0.id == item.id } }

    func state(for project: Project) -> ProjectWorkflowState { projectStates[project.folderURL.path] ?? ProjectWorkflowState() }

    func isResolved(_ item: StudioWorkflowItem, for project: Project) -> Bool {
        StudioWorkflowResolver.isResolved(item, state: state(for: project))
    }

    func coreProgress(for project: Project, stage: ProjectStage) -> (resolved: Int, total: Int) {
        StudioWorkflowResolver.coreProgress(stage: stage, items: items, state: state(for: project))
    }

    func nextUnresolvedCore(for project: Project, stage: ProjectStage) -> StudioWorkflowItem? {
        StudioWorkflowResolver.nextUnresolvedCore(stage: stage, items: items, state: state(for: project))
    }

    func shouldSuggestAdvance(for project: Project, stage: ProjectStage) -> Bool {
        let progress = coreProgress(for: project, stage: stage)
        return progress.total > 0 && progress.resolved == progress.total && !state(for: project).dismissedSuggestions.contains(stage)
    }

    func toggle(_ item: StudioWorkflowItem, for project: Project) {
        updateState(for: project, stage: item.stage) { state in
            if state.completedItemIDs.contains(item.id) { state.completedItemIDs.remove(item.id) }
            else { state.completedItemIDs.insert(item.id) }
        }
    }

    func answerBinding(for item: StudioWorkflowItem, project: Project) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.state(for: project).answers[item.id] ?? "" },
            set: { [weak self] answer in self?.setAnswer(answer, for: item, project: project) }
        )
    }

    func answer(for item: StudioWorkflowItem, project: Project) -> String { state(for: project).answers[item.id] ?? "" }

    func dismissSuggestion(for project: Project, stage: ProjectStage) {
        var state = self.state(for: project)
        state.dismissedSuggestions.insert(stage)
        projectStates[project.folderURL.path] = state
        saveProjects()
    }

    func addCustomItem(stage: ProjectStage) {
        let nextOrder = (items(for: stage).map(\.order).max() ?? 0) + 10
        customization.customItems.append(.init(
            id: "custom.\(UUID().uuidString.lowercased())", stage: stage, section: "My prompts",
            kind: .checklist, importance: .optional, title: "New workflow item", detail: "", order: nextOrder
        ))
        saveTemplate()
    }

    func updateItem(_ item: StudioWorkflowItem) {
        if let index = customization.customItems.firstIndex(where: { $0.id == item.id }) {
            customization.customItems[index] = item
        } else if let original = builtInItems.first(where: { $0.id == item.id }) {
            customization.overrides[item.id] = .init(
                stage: item.stage == original.stage ? nil : item.stage,
                section: item.section == original.section ? nil : item.section,
                kind: item.kind == original.kind ? nil : item.kind,
                importance: item.importance == original.importance ? nil : item.importance,
                title: item.title == original.title ? nil : item.title,
                detail: item.detail == original.detail ? nil : item.detail,
                order: item.order == original.order ? nil : item.order
            )
        }
        saveTemplate()
    }

    func removeItem(_ item: StudioWorkflowItem) {
        if isBuiltIn(item) { customization.hiddenBuiltInIDs.insert(item.id) }
        else { customization.customItems.removeAll { $0.id == item.id } }
        saveTemplate()
    }

    func restoreItem(_ item: StudioWorkflowItem) {
        customization.hiddenBuiltInIDs.remove(item.id)
        customization.overrides.removeValue(forKey: item.id)
        saveTemplate()
    }

    func restoreStage(_ stage: ProjectStage) {
        let ids = Set(builtInItems.filter { $0.stage == stage }.map(\.id))
        customization.hiddenBuiltInIDs.subtract(ids)
        customization.overrides = customization.overrides.filter { !ids.contains($0.key) }
        customization.customItems.removeAll { $0.stage == stage }
        saveTemplate()
    }

    func restoreAll() {
        customization = StudioWorkflowCustomization()
        saveTemplate()
    }

    func moveItem(_ item: StudioWorkflowItem, direction: Int) {
        let stageItems = items(for: item.stage)
        guard let index = stageItems.firstIndex(where: { $0.id == item.id }) else { return }
        let target = index + direction
        guard stageItems.indices.contains(target) else { return }
        var moved = item
        var swapped = stageItems[target]
        let order = moved.order
        moved.order = swapped.order
        swapped.order = order
        updateItem(moved)
        updateItem(swapped)
    }

    private func setAnswer(_ answer: String, for item: StudioWorkflowItem, project: Project) {
        updateState(for: project, stage: item.stage) { state in
            if answer.isEmpty { state.answers.removeValue(forKey: item.id) }
            else { state.answers[item.id] = answer }
        }
    }

    private func updateState(for project: Project, stage: ProjectStage, change: (inout ProjectWorkflowState) -> Void) {
        var state = self.state(for: project)
        change(&state)
        state.dismissedSuggestions.remove(stage)
        projectStates[project.folderURL.path] = state
        saveProjects()
    }

    private func saveTemplate() {
        objectWillChange.send()
        Self.save(customization, to: templateURL)
    }

    private func saveProjects() { Self.save(projectStates, to: projectsURL) }

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
