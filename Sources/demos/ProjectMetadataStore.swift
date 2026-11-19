import Foundation

enum ProjectKeyAccidental: String, CaseIterable, Identifiable {
    case flat = "♭"
    case natural = ""
    case sharp = "♯"

    var id: String { rawValue }
    var pickerTitle: String { self == .natural ? "♮" : rawValue }
    var spokenTitle: String {
        switch self {
        case .flat: return "Flat"
        case .natural: return "Natural"
        case .sharp: return "Sharp"
        }
    }
}

enum ProjectKeyMode: String, CaseIterable, Identifiable {
    case major
    case minor
    case dorian
    case mixolydian
    case lydian
    case phrygian
    case locrian
    case wholeTone = "whole tone"
    case halfWholeDiminished = "half-whole diminished"
    case wholeHalfDiminished = "whole-half diminished"
    case minorBlues = "minor blues"
    case minorPentatonic = "minor pentatonic"
    case majorPentatonic = "major pentatonic"
    case harmonicMinor = "harmonic minor"
    case harmonicMajor = "harmonic major"
    case dorianSharpFour = "dorian #4"
    case phrygianDominant = "phrygian dominant"
    case melodicMinor = "melodic minor"
    case lydianAugmented = "lydian augmented"
    case lydianDominant = "lydian dominant"
    case superLocrian = "super locrian"
    case eightToneSpanish = "8-tone spanish"
    case bhairav
    case hungarianMinor = "hungarian minor"
    case hirajoshi
    case inSen = "in-sen"
    case iwato
    case kumoi
    case pelogSelisir = "pelog selisir"
    case pelogTembung = "pelog tembung"
    case messiaenThree = "messiaen 3"
    case messiaenFour = "messiaen 4"
    case messiaenFive = "messiaen 5"
    case messiaenSix = "messiaen 6"
    case messiaenSeven = "messiaen 7"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .halfWholeDiminished: return "Half-whole Dim."
        case .wholeHalfDiminished: return "Whole-half Dim."
        case .dorianSharpFour: return "Dorian #4"
        case .eightToneSpanish: return "8-Tone Spanish"
        case .inSen: return "In-Sen"
        default: return rawValue.capitalized
        }
    }
    var storedTitle: String {
        switch self {
        case .dorianSharpFour: return "Dorian #4"
        case .eightToneSpanish: return "8-Tone Spanish"
        case .inSen: return "In-Sen"
        default: return rawValue.capitalized
        }
    }
    var compactTitle: String { title }
}

struct ProjectMusicalKeySelection: Equatable {
    var note: String
    var accidental: ProjectKeyAccidental
    var mode: ProjectKeyMode

    var displayName: String { "\(note)\(accidental.rawValue) \(mode.storedTitle)" }
}

enum ProjectMusicalKeys {
    static let notes = ["C", "D", "E", "F", "G", "A", "B"]

    static func selection(from storedValue: String?) -> ProjectMusicalKeySelection? {
        guard let storedValue else { return nil }
        let trimmed = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        guard let mode = ProjectKeyMode.allCases
            .sorted(by: { $0.rawValue.count > $1.rawValue.count })
            .first(where: { lowercased.hasSuffix(" \($0.rawValue)") }) else {
            return nil
        }

        let root = String(trimmed.dropLast(mode.rawValue.count + 1))
            .components(separatedBy: "/")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let noteCharacter = root.first else { return nil }
        let note = String(noteCharacter).uppercased()
        guard notes.contains(note) else { return nil }

        let accidental: ProjectKeyAccidental
        if root.contains("♭") || root.dropFirst().lowercased().hasPrefix("b") {
            accidental = .flat
        } else if root.contains("♯") || root.contains("#") {
            accidental = .sharp
        } else {
            accidental = .natural
        }
        return ProjectMusicalKeySelection(note: note, accidental: accidental, mode: mode)
    }
}

enum ProjectRating: String, Codable, CaseIterable, Identifiable {
    case s = "S", a = "A", b = "B", c = "C", d = "D", f = "F"
    var id: String { rawValue }
}

enum ProjectPriority: Int, Codable, CaseIterable, Identifiable {
    case p1 = 1, p2, p3, p4, p5
    var id: Int { rawValue }
    var title: String { "P\(rawValue)" }
}

enum ProjectKind: String, Codable, CaseIterable, Identifiable {
    case personal = "Personal"
    case client = "Client"
    var id: String { rawValue }
}

enum ProductionPhase: String, Codable, CaseIterable, Identifiable {
    case sketching = "SKETCHING"
    case producing = "PRODUCING"
    case mixing = "MIXING"
    case masteringPolishing = "MASTERING / POLISHING"

    var id: String { rawValue }
    var title: String { rawValue }

    var shortTitle: String {
        switch self {
        case .sketching: return "Sketch"
        case .producing: return "Produce"
        case .mixing: return "Mix"
        case .masteringPolishing: return "Master"
        }
    }

    var icon: String {
        switch self {
        case .sketching: return "pencil.and.outline"
        case .producing: return "waveform.badge.plus"
        case .mixing: return "slider.vertical.3"
        case .masteringPolishing: return "sparkles"
        }
    }

    var suggestedTasks: [String] {
        switch self {
        case .sketching:
            return ["Melody / topline idea", "Chord progression", "Drum rhythm skeleton", "Sound palette choice"]
        case .producing:
            return ["Intro to drop build", "Drum fills & transitions", "Second verse variation", "FX sweeps & impacts"]
        case .mixing:
            return ["Vocal EQ & de-ess", "Kick & bass low-end mono", "Reverb / delay space", "Automation rides"]
        case .masteringPolishing:
            return ["Target LUFS & true peak", "Car & phone speaker check", "Export full WAV & stems", "Client preview review"]
        }
    }
}

enum ClientWorkflowScope: String, Codable, CaseIterable, Identifiable {
    case full = "Full Production"
    case mixAndMaster = "Mixing & Mastering"
    case masteringOnly = "Mastering Only"

    var id: String { rawValue }
    var title: String { rawValue }

    var allowedPhases: [ProductionPhase] {
        switch self {
        case .full:
            return [.sketching, .producing, .mixing, .masteringPolishing]
        case .mixAndMaster:
            return [.mixing, .masteringPolishing]
        case .masteringOnly:
            return [.masteringPolishing]
        }
    }
}

enum AudioServiceType: String, Codable, CaseIterable, Identifiable {
    case mixing = "Mixing"
    case mastering = "Mastering"
    case stemMastering = "Stem Mastering"
    case production = "Production"
    case recording = "Recording"
    var id: String { rawValue }
}

struct DeliverableItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var isCompleted: Bool = false

    static let standardMixMasterDeliverables: [DeliverableItem] = [
        DeliverableItem(title: "Main Mix (24/48k WAV)"),
        DeliverableItem(title: "Streaming Master (-14 LUFS)"),
        DeliverableItem(title: "Club / Loud Master"),
        DeliverableItem(title: "Instrumental"),
        DeliverableItem(title: "Acapella"),
        DeliverableItem(title: "TV Track (Lead Muted)"),
        DeliverableItem(title: "Clean / Radio Edit"),
        DeliverableItem(title: "Stems / Multitracks")
    ]
}

struct ProjectRevisionItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var timestampSeconds: Double? = nil
    var timestampLabel: String? = nil
    var text: String
    var isResolved: Bool = false
    var createdDate: Date = Date()
}

struct ProjectMetadata: Codable {
    var rating: ProjectRating? = nil
    var priority: ProjectPriority? = nil
    var musicalKey: String? = nil
    var projectKind: ProjectKind? = nil
    var clientName: String? = nil
    var serviceType: AudioServiceType? = nil
    var clientWorkflowScope: ClientWorkflowScope? = nil
    var productionPhase: ProductionPhase? = nil
    var targetDeadline: Date? = nil
    var dropboxFolderPath: String? = nil
    var dropboxShareLink: String? = nil
    var targetLUFS: Double? = nil
    var manualDeliverables: [DeliverableItem]? = nil
    var revisions: [ProjectRevisionItem]? = nil
    var personalCategory: String? = nil
}

@MainActor
final class ProjectMetadataStore: ObservableObject {
    @Published private var values: [String: ProjectMetadata] = [:]
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("Backstage", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("project-metadata.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([String: ProjectMetadata].self, from: data) {
            values = saved
        }
    }

    func metadata(for project: Project) -> ProjectMetadata {
        values[project.folderURL.path] ?? ProjectMetadata()
    }

    func setRating(_ rating: ProjectRating?, for project: Project) {
        update(project) { $0.rating = rating }
    }

    func setPriority(_ priority: ProjectPriority?, for project: Project) {
        update(project) { $0.priority = priority }
    }

    func setMusicalKey(_ key: String?, for project: Project) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        update(project) { $0.musicalKey = trimmed.isEmpty ? nil : trimmed }
    }

    func setProjectKind(_ kind: ProjectKind?, for project: Project) {
        update(project) { $0.projectKind = kind }
    }

    func setClientName(_ name: String?, for project: Project) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        update(project) { $0.clientName = trimmed.isEmpty ? nil : trimmed }
    }

    func setPersonalCategory(_ category: String?, for project: Project) {
        let trimmed = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        update(project) { $0.personalCategory = trimmed.isEmpty ? nil : trimmed }
    }

    func setPersonalCategory(_ category: String?, forPath path: String) {
        var meta = values[path] ?? ProjectMetadata()
        let trimmed = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        meta.personalCategory = trimmed.isEmpty ? nil : trimmed
        values[path] = meta
        save()
    }

    func setServiceType(_ type: AudioServiceType?, for project: Project) {
        update(project) { $0.serviceType = type }
    }

    func setProductionPhase(_ phase: ProductionPhase?, for project: Project) {
        update(project) { $0.productionPhase = phase }
    }

    func setClientWorkflowScope(_ scope: ClientWorkflowScope?, for project: Project) {
        update(project) { $0.clientWorkflowScope = scope }
    }

    func effectiveClientScope(for project: Project) -> ClientWorkflowScope {
        let meta = metadata(for: project)
        if let explicit = meta.clientWorkflowScope {
            return explicit
        }
        if let service = meta.serviceType {
            switch service {
            case .mastering, .stemMastering:
                return .masteringOnly
            case .mixing:
                return .mixAndMaster
            default:
                return .full
            }
        }
        return .full
    }

    func effectivePhases(for project: Project) -> [ProductionPhase] {
        let meta = metadata(for: project)
        if meta.projectKind == .client {
            return effectiveClientScope(for: project).allowedPhases
        } else {
            return ProductionPhase.allCases
        }
    }

    func advanceToNextPhase(for project: Project) {
        let available = effectivePhases(for: project)
        guard !available.isEmpty else { return }
        let current = metadata(for: project).productionPhase
        if let current, let idx = available.firstIndex(of: current) {
            let nextIdx = (idx + 1) % available.count
            setProductionPhase(available[nextIdx], for: project)
        } else {
            setProductionPhase(available.first, for: project)
        }
    }

    func setTargetDeadline(_ date: Date?, for project: Project) {
        update(project) { $0.targetDeadline = date }
    }

    func setDropboxFolderPath(_ path: String?, for project: Project) {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        update(project) { $0.dropboxFolderPath = trimmed.isEmpty ? nil : trimmed }
    }

    func setDropboxShareLink(_ link: String?, for project: Project) {
        let trimmed = link?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        update(project) { $0.dropboxShareLink = trimmed.isEmpty ? nil : trimmed }
    }

    func setTargetLUFS(_ lufs: Double?, for project: Project) {
        update(project) { $0.targetLUFS = lufs }
    }

    func setDeliverables(_ items: [DeliverableItem], for project: Project) {
        update(project) { $0.manualDeliverables = items }
    }

    func toggleDeliverable(_ id: UUID, for project: Project) {
        update(project) { meta in
            var items = meta.manualDeliverables ?? DeliverableItem.standardMixMasterDeliverables
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx].isCompleted.toggle()
                meta.manualDeliverables = items
            }
        }
    }

    func addDeliverable(title: String, for project: Project) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(project) { meta in
            var items = meta.manualDeliverables ?? DeliverableItem.standardMixMasterDeliverables
            items.append(DeliverableItem(title: trimmed))
            meta.manualDeliverables = items
        }
    }

    func deleteDeliverable(_ id: UUID, for project: Project) {
        update(project) { meta in
            var items = meta.manualDeliverables ?? DeliverableItem.standardMixMasterDeliverables
            items.removeAll { $0.id == id }
            meta.manualDeliverables = items
        }
    }

    func setRevisions(_ items: [ProjectRevisionItem], for project: Project) {
        update(project) { $0.revisions = items }
    }

    func addRevision(text: String, timestampSeconds: Double? = nil, timestampLabel: String? = nil, for project: Project) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(project) { meta in
            var list = meta.revisions ?? []
            list.append(ProjectRevisionItem(
                timestampSeconds: timestampSeconds,
                timestampLabel: timestampLabel,
                text: trimmed,
                isResolved: false
            ))
            meta.revisions = list
        }
    }

    func toggleRevision(_ id: UUID, for project: Project) {
        update(project) { meta in
            var list = meta.revisions ?? []
            if let idx = list.firstIndex(where: { $0.id == id }) {
                list[idx].isResolved.toggle()
                meta.revisions = list
            }
        }
    }

    func deleteRevision(_ id: UUID, for project: Project) {
        update(project) { meta in
            var list = meta.revisions ?? []
            list.removeAll { $0.id == id }
            meta.revisions = list
        }
    }

    func migratePath(from oldPath: String, to newPath: String) {
        guard let meta = values.removeValue(forKey: oldPath) else { return }
        values[newPath] = meta
        save()
    }

    func setProjectKind(_ kind: ProjectKind?, forPath path: String) {
        var meta = values[path] ?? ProjectMetadata()
        meta.projectKind = kind
        values[path] = meta
        save()
    }

    func setClientName(_ name: String?, forPath path: String) {
        var meta = values[path] ?? ProjectMetadata()
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        meta.clientName = trimmed.isEmpty ? nil : trimmed
        values[path] = meta
        save()
    }

    private func update(_ project: Project, change: (inout ProjectMetadata) -> Void) {
        var metadata = self.metadata(for: project)
        change(&metadata)
        values[project.folderURL.path] = metadata
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(values) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
