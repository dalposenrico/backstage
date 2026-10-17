import AppKit
import Foundation

enum UntitledSyncStatus: Equatable {
    case notSynced
    case sending
    case synced
    case updateAvailable
}

private struct UntitledSyncRecord: Codable {
    var state: String
    var fileSize: Int64
    var modificationDate: Date?
    var updatedAt: Date
}

enum UntitledDestinationMode: String, Codable {
    case newVersion
    case newTrack
}

struct UntitledDestination: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var mode: UntitledDestinationMode
    var isSongProject: Bool
}

struct UntitledSendDraft: Identifiable {
    let id = UUID()
    let track: Track
    let project: Project
    var destinations: [UntitledDestination]
    var selectedDestinationIDs: Set<UUID>
}

private struct UntitledMacroPayload: Codable {
    let filePath: String
    let projectName: String
    let destinations: [UntitledDestination]
}

@MainActor
final class UntitledSyncStore: ObservableObject {
    static let macroName = "Automate Untitled Uploads"

    @Published private var records: [String: UntitledSyncRecord] = [:]
    @Published private(set) var destinations: [UntitledDestination] = []
    @Published var draft: UntitledSendDraft?

    private var projectSelections: [String: Set<UUID>] = [:]

    private static let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("Backstage", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("untitled-sync.json")
    }()

    private static let handoffFileURL: URL = {
        fileURL.deletingLastPathComponent().appendingPathComponent("untitled-handoff.json")
    }()

    private static let destinationsFileURL: URL = {
        fileURL.deletingLastPathComponent().appendingPathComponent("untitled-destinations.json")
    }()

    private struct DestinationSettings: Codable {
        var destinations: [UntitledDestination]
        var projectSelections: [String: Set<UUID>]
    }

    init() {
        load()
        loadDestinations()
    }

    func status(for track: Track) -> UntitledSyncStatus {
        guard let record = records[track.url.path] else { return .notSynced }
        guard record.state == "synced" else { return .sending }
        let attributes = try? FileManager.default.attributesOfItem(atPath: track.url.path)
        let currentSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let currentDate = attributes?[.modificationDate] as? Date
        return currentSize == record.fileSize && currentDate == record.modificationDate
            ? .synced
            : .updateAvailable
    }

    func send(_ track: Track, project: Project) {
        prepare(track, project: project)
        sendDraft()
    }

    func prepare(_ track: Track, project: Project) {
        let songDestination = UntitledDestination(
            id: songDestinationID(for: project),
            name: project.name,
            mode: .newVersion,
            isSongProject: true
        )
        let extras = destinations.filter { !$0.isSongProject }
        let remembered = projectSelections[project.folderURL.path] ?? []
        draft = UntitledSendDraft(
            track: track,
            project: project,
            destinations: [songDestination] + extras,
            selectedDestinationIDs: remembered.union([songDestination.id])
        )
    }

    func toggleDestination(_ destination: UntitledDestination) {
        guard var draft else { return }
        if draft.selectedDestinationIDs.contains(destination.id) {
            if !destination.isSongProject { draft.selectedDestinationIDs.remove(destination.id) }
        } else {
            draft.selectedDestinationIDs.insert(destination.id)
        }
        self.draft = draft
    }

    func addDestination(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !destinations.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame })
        else { return }
        let destination = UntitledDestination(id: UUID(), name: name, mode: .newTrack, isSongProject: false)
        destinations.append(destination)
        saveDestinations()
        if var draft {
            draft.destinations.append(destination)
            draft.selectedDestinationIDs.insert(destination.id)
            self.draft = draft
        }
    }

    func removeDestination(_ destination: UntitledDestination) {
        guard !destination.isSongProject else { return }
        destinations.removeAll { $0.id == destination.id }
        for key in projectSelections.keys { projectSelections[key]?.remove(destination.id) }
        if var draft {
            draft.destinations.removeAll { $0.id == destination.id }
            draft.selectedDestinationIDs.remove(destination.id)
            self.draft = draft
        }
        saveDestinations()
    }

    func sendDraft() {
        guard let draft else { return }
        let selected = draft.destinations.filter { draft.selectedDestinationIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        projectSelections[draft.project.folderURL.path] = Set(
            selected.filter { !$0.isSongProject }.map(\.id)
        )
        saveDestinations()

        guard let payload = try? JSONEncoder().encode(
            UntitledMacroPayload(
                filePath: draft.track.url.path,
                projectName: draft.project.name,
                destinations: selected
            )
        ) else { return }
        do {
            try payload.write(to: Self.handoffFileURL, options: .atomic)
        } catch {
            print("[untitled] handoff file failed: \(error.localizedDescription)")
            return
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: draft.track.url.path)
        records[draft.track.url.path] = UntitledSyncRecord(
            state: "sending",
            fileSize: (attributes?[.size] as? NSNumber)?.int64Value ?? 0,
            modificationDate: attributes?[.modificationDate] as? Date,
            updatedAt: .now
        )
        save()

        NSWorkspace.shared.openApplication(
            at: untitledApplicationURL,
            configuration: .init()
        ) { _, _ in
            Task { @MainActor in
                self.runMacro()
            }
        }
    }

    private func songDestinationID(for project: Project) -> UUID {
        let bytes = Array(project.folderURL.path.utf8)
        var hash: UInt64 = 1469598103934665603
        for byte in bytes { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        let suffix = String(format: "%012llx", hash & 0xFFFFFFFFFFFF)
        return UUID(uuidString: "00000000-0000-4000-8000-\(suffix)") ?? UUID()
    }

    func markSynced(_ track: Track) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: track.url.path)
        records[track.url.path] = UntitledSyncRecord(
            state: "synced",
            fileSize: (attributes?[.size] as? NSNumber)?.int64Value ?? 0,
            modificationDate: attributes?[.modificationDate] as? Date,
            updatedAt: .now
        )
        save()
    }

    func reset(_ track: Track) {
        records.removeValue(forKey: track.url.path)
        save()
    }

    private var untitledApplicationURL: URL {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.untitledinbrackets.untitled-macos")
            ?? URL(fileURLWithPath: "/Applications/[untitled].app")
    }

    private func runMacro() {
        guard let keyboardMaestro = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.stairways.keyboardmaestro.editor"
        ) else { return }

        let process = Process()
        process.executableURL = keyboardMaestro.appendingPathComponent("Contents/MacOS/keyboardmaestro")
        process.arguments = ["--async", Self.macroName]
        try? process.run()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode([String: UntitledSyncRecord].self, from: data)
        else { return }
        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    private func loadDestinations() {
        guard let data = try? Data(contentsOf: Self.destinationsFileURL),
              let settings = try? JSONDecoder().decode(DestinationSettings.self, from: data)
        else { return }
        destinations = settings.destinations
        projectSelections = settings.projectSelections
    }

    private func saveDestinations() {
        let settings = DestinationSettings(destinations: destinations, projectSelections: projectSelections)
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: Self.destinationsFileURL, options: .atomic)
    }
}
