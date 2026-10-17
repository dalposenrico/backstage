import Foundation

struct ProjectTodo: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    let createdAt: Date

    init(id: UUID = UUID(), title: String, isCompleted: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }
}

@MainActor
final class ProjectTodoStore: ObservableObject {
    @Published private var values: [String: [ProjectTodo]] = [:]
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("Backstage", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("project-todos.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([String: [ProjectTodo]].self, from: data) {
            values = saved
        }
    }

    func todos(for project: Project) -> [ProjectTodo] {
        values[project.folderURL.path] ?? []
    }

    func openTodos(for project: Project) -> [ProjectTodo] {
        todos(for: project).filter { !$0.isCompleted }
    }

    func add(_ title: String, to project: Project) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        values[project.folderURL.path, default: []].append(ProjectTodo(title: trimmed))
        save()
    }

    func toggle(_ todo: ProjectTodo, for project: Project) {
        guard let index = values[project.folderURL.path]?.firstIndex(where: { $0.id == todo.id }) else { return }
        values[project.folderURL.path]?[index].isCompleted.toggle()
        save()
    }

    func remove(_ todo: ProjectTodo, from project: Project) {
        values[project.folderURL.path]?.removeAll { $0.id == todo.id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(values) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
