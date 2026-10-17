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

struct ProjectMetadata: Codable {
    var rating: ProjectRating? = nil
    var priority: ProjectPriority? = nil
    var musicalKey: String? = nil
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

    private func update(_ project: Project, change: (inout ProjectMetadata) -> Void) {
        var metadata = self.metadata(for: project)
        change(&metadata)
        values[project.folderURL.path] = metadata
        guard let data = try? JSONEncoder().encode(values) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
