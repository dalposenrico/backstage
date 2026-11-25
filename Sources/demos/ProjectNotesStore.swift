import Foundation
import SwiftUI

@MainActor
final class ProjectNotesStore: ObservableObject {
    static weak var shared: ProjectNotesStore?
    @Published private var notes: [String: String] = [:]
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("Backstage", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("project-notes.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            notes = saved
        }
        Self.shared = self
    }

    func note(for project: Project) -> String {
        notes[project.folderURL.path] ?? ""
    }

    func binding(for project: Project) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.note(for: project) ?? "" },
            set: { [weak self] value in self?.setNote(value, for: project) }
        )
    }

    func append(_ block: String, for project: Project) {
        let existing = note(for: project).trimmingCharacters(in: .whitespacesAndNewlines)
        setNote(existing.isEmpty ? block : existing + "\n\n" + block, for: project)
    }

    private func setNote(_ note: String, for project: Project) {
        let path = project.folderURL.path
        let existing = notes[path] ?? ""
        guard existing != note else { return }
        if note.isEmpty { notes.removeValue(forKey: path) }
        else { notes[path] = note }
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
