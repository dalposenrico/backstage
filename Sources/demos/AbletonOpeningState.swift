import Foundation

enum AbletonOpeningPhase: String, Equatable, Sendable {
    case opening
    case loaded
}

struct AbletonOpeningState: Equatable, Sendable {
    let projectID: Project.ID
    let folderURL: URL
    let projectName: String
    let targetVersionURL: URL
    let startedAt: Date
    var phase: AbletonOpeningPhase

    init(
        projectID: Project.ID,
        folderURL: URL,
        projectName: String,
        targetVersionURL: URL,
        startedAt: Date = Date(),
        phase: AbletonOpeningPhase = .opening
    ) {
        self.projectID = projectID
        self.folderURL = folderURL
        self.projectName = projectName
        self.targetVersionURL = targetVersionURL
        self.startedAt = startedAt
        self.phase = phase
    }

    func matchesLoadedProject(folderURL: URL?) -> Bool {
        guard let folderURL else { return false }
        return self.folderURL.standardizedFileURL.path == folderURL.standardizedFileURL.path
    }

    func hasTimedOut(at now: Date = Date(), timeoutInterval: TimeInterval = 60) -> Bool {
        now.timeIntervalSince(startedAt) >= timeoutInterval
    }
}
