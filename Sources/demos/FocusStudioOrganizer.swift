import Foundation
import SwiftUI

// MARK: - Deadline Urgency

enum DeadlineUrgency: Equatable, Comparable {
    case overdue(days: Int)
    case dueToday
    case dueTomorrow
    case dueSoon(days: Int)
    case thisWeek(Date)
    case upcoming(Date)
    case noDeadline

    var title: String {
        switch self {
        case .overdue(let days):
            return days <= 1 ? "Overdue (1 day)" : "Overdue (\(days) days)"
        case .dueToday:
            return "Due today"
        case .dueTomorrow:
            return "Due tomorrow"
        case .dueSoon(let days):
            return "Due in \(days) days"
        case .thisWeek(let date):
            return "Due \(Self.shortDate(date))"
        case .upcoming(let date):
            return "Due \(Self.shortDate(date))"
        case .noDeadline:
            return "No deadline"
        }
    }

    var shortBadge: String {
        switch self {
        case .overdue(let days):
            return days <= 1 ? "1d overdue" : "\(days)d overdue"
        case .dueToday:
            return "Today"
        case .dueTomorrow:
            return "Tomorrow"
        case .dueSoon(let days):
            return "\(days)d left"
        case .thisWeek(let date), .upcoming(let date):
            return Self.shortDate(date)
        case .noDeadline:
            return "Flexible"
        }
    }

    var isUrgent: Bool {
        switch self {
        case .overdue, .dueToday, .dueTomorrow, .dueSoon:
            return true
        default:
            return false
        }
    }

    var badgeColor: Color {
        switch self {
        case .overdue:
            return Color(hex: "FF5C5C")
        case .dueToday:
            return Color(hex: "FF8A00")
        case .dueTomorrow:
            return Color(hex: "FFAA2C")
        case .dueSoon:
            return Color.accent
        case .thisWeek:
            return Color.secondaryText
        case .upcoming:
            return Color.secondaryText
        case .noDeadline:
            return Color.tertiaryText
        }
    }

    var badgeBackground: Color {
        badgeColor.opacity(0.14)
    }

    var sortOrder: Int {
        switch self {
        case .overdue(let days): return -1000 - days
        case .dueToday: return 0
        case .dueTomorrow: return 1
        case .dueSoon(let days): return 10 + days
        case .thisWeek: return 100
        case .upcoming: return 200
        case .noDeadline: return 999
        }
    }

    static func < (lhs: DeadlineUrgency, rhs: DeadlineUrgency) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    static func calculate(from deadline: Date?, referenceDate: Date = Date(), calendar: Calendar = .current) -> DeadlineUrgency {
        guard let deadline else { return .noDeadline }

        let startOfRef = calendar.startOfDay(for: referenceDate)
        let startOfDeadline = calendar.startOfDay(for: deadline)

        let components = calendar.dateComponents([.day], from: startOfRef, to: startOfDeadline)
        let days = components.day ?? 0

        if days < 0 {
            return .overdue(days: abs(days))
        } else if days == 0 {
            return .dueToday
        } else if days == 1 {
            return .dueTomorrow
        } else if days <= 3 {
            return .dueSoon(days: days)
        } else if days <= 7 {
            return .thisWeek(deadline)
        } else {
            return .upcoming(deadline)
        }
    }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Focus Studio View Mode

enum FocusStudioViewMode: String, CaseIterable, Identifiable {
    case split = "Both (Split)"
    case clientsExpanded = "Clients Only"
    case personalExpanded = "Personal Only"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .split: return "rectangle.split.2x1"
        case .clientsExpanded: return "person.2"
        case .personalExpanded: return "music.note.house"
        }
    }
}

// MARK: - Focus Actionable Item

struct FocusActionableItem: Identifiable, Equatable {
    var id: Project.ID { project.id }
    let project: Project
    let metadata: ProjectMetadata
    let todos: [ProjectTodo]
    let progress: ProjectProgress
    let urgency: DeadlineUrgency
    let isClient: Bool
    let clientName: String
    let personalCategory: String

    init(
        project: Project,
        metadata: ProjectMetadata,
        todos: [ProjectTodo],
        progress: ProjectProgress,
        urgency: DeadlineUrgency,
        clientBaseURL: URL? = nil,
        rootURL: URL? = nil,
        isClient: Bool? = nil,
        clientName: String? = nil,
        personalCategory: String? = nil
    ) {
        self.project = project
        self.metadata = metadata
        self.todos = todos
        self.progress = progress
        self.urgency = urgency

        if let isClient, let clientName {
            self.isClient = isClient
            self.clientName = clientName
        } else if let clientBaseURL {
            let resolved = FocusStudioOrganizer.resolveClientStatus(
                project: project,
                metadata: metadata,
                clientBaseURL: clientBaseURL
            )
            self.isClient = isClient ?? resolved.isClient
            self.clientName = clientName ?? resolved.clientName
        } else {
            let trimmedMetadataName = metadata.clientName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if metadata.projectKind == .personal {
                self.isClient = false
                self.clientName = ""
            } else if !trimmedMetadataName.isEmpty {
                self.isClient = true
                self.clientName = trimmedMetadataName
            } else if metadata.projectKind == .client {
                self.isClient = true
                self.clientName = "Direct / Independent"
            } else {
                self.isClient = false
                self.clientName = ""
            }
        }

        self.personalCategory = personalCategory ?? FocusStudioOrganizer.derivePersonalCategory(
            project: project,
            metadata: metadata,
            rootURL: rootURL
        )
    }

    var effectiveDeliverables: [DeliverableItem] {
        metadata.manualDeliverables ?? DeliverableItem.standardMixMasterDeliverables
    }

    var completedDeliverablesCount: Int {
        effectiveDeliverables.filter(\.isCompleted).count
    }

    var totalDeliverablesCount: Int {
        effectiveDeliverables.count
    }

    var unresolvedRevisions: [ProjectRevisionItem] {
        (metadata.revisions ?? []).filter { !$0.isResolved }
    }

    var openTodos: [ProjectTodo] {
        todos.filter { !$0.isCompleted }
    }

    var hasPendingWork: Bool {
        if isClient {
            return completedDeliverablesCount < totalDeliverablesCount || !unresolvedRevisions.isEmpty || !openTodos.isEmpty
        } else {
            return !openTodos.isEmpty || !progress.nextMove.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static func == (lhs: FocusActionableItem, rhs: FocusActionableItem) -> Bool {
        lhs.id == rhs.id
            && lhs.isClient == rhs.isClient
            && lhs.clientName == rhs.clientName
            && lhs.personalCategory == rhs.personalCategory
            && lhs.urgency == rhs.urgency
            && lhs.metadata.projectKind == rhs.metadata.projectKind
            && lhs.metadata.clientName == rhs.metadata.clientName
            && lhs.metadata.personalCategory == rhs.metadata.personalCategory
            && lhs.metadata.targetDeadline == rhs.metadata.targetDeadline
            && lhs.metadata.productionPhase == rhs.metadata.productionPhase
            && lhs.completedDeliverablesCount == rhs.completedDeliverablesCount
            && lhs.unresolvedRevisions.count == rhs.unresolvedRevisions.count
            && lhs.openTodos.count == rhs.openTodos.count
            && lhs.progress.stage == rhs.progress.stage
            && lhs.progress.nextMove == rhs.progress.nextMove
    }
}

// MARK: - Client Group

struct FocusClientGroup: Identifiable {
    var id: String { clientName }
    let clientName: String
    let items: [FocusActionableItem]

    var mostUrgentDeadline: DeadlineUrgency {
        items.map(\.urgency).min() ?? .noDeadline
    }

    var totalOpenTasks: Int {
        items.reduce(0) { total, item in
            let pendingDeliverables = item.totalDeliverablesCount - item.completedDeliverablesCount
            return total + pendingDeliverables + item.unresolvedRevisions.count + item.openTodos.count
        }
    }
}

// MARK: - Category Group (for Personal Music)

struct FocusCategoryGroup: Identifiable {
    var id: String { categoryName }
    let categoryName: String
    let items: [FocusActionableItem]

    var mostUrgentDeadline: DeadlineUrgency {
        items.map(\.urgency).min() ?? .noDeadline
    }

    var totalOpenTodos: Int {
        items.reduce(0) { $0 + $1.openTodos.count }
    }
}

// MARK: - Organizer Functions

@MainActor
enum FocusStudioOrganizer {
    nonisolated static let unassignedClientName = "No Client Assigned"

    /// Checks if a project URL is located anywhere inside the base client work URL.
    nonisolated static func isProjectInsideBaseURL(_ projectURL: URL, baseURL: URL) -> Bool {
        let standardizedProject = projectURL.standardizedFileURL.resolvingSymlinksInPath()
        let standardizedBase = baseURL.standardizedFileURL.resolvingSymlinksInPath()

        let baseComponents = standardizedBase.pathComponents
        let projComponents = standardizedProject.pathComponents

        guard projComponents.count > baseComponents.count else { return false }

        for i in 0..<baseComponents.count {
            if projComponents[i] != baseComponents[i] {
                return false
            }
        }
        return true
    }

    /// Derives the client name from the folder hierarchy if inside baseURL (e.g. baseURL/Client/Project -> Client).
    /// If directly in baseURL (baseURL/Project), returns nil (unassigned client).
    nonisolated static func deriveClientNameFromFolder(projectURL: URL, baseURL: URL) -> String? {
        let standardizedProject = projectURL.standardizedFileURL.resolvingSymlinksInPath()
        let standardizedBase = baseURL.standardizedFileURL.resolvingSymlinksInPath()

        let baseComponents = standardizedBase.pathComponents
        let projComponents = standardizedProject.pathComponents

        guard projComponents.count > baseComponents.count else { return nil }

        for i in 0..<baseComponents.count {
            if projComponents[i] != baseComponents[i] {
                return nil
            }
        }

        let relativeComponents = Array(projComponents[baseComponents.count...])
        // If directly inside baseURL (relativeComponents.count <= 1), there is no client subfolder
        if relativeComponents.count <= 1 {
            return nil
        }

        let firstFolder = relativeComponents[0].trimmingCharacters(in: .whitespacesAndNewlines)
        return firstFolder.isEmpty ? nil : firstFolder
    }

    /// Derives the category for personal projects (e.g. Portfolio, Singles, or Uncategorized).
    nonisolated static func derivePersonalCategory(
        project: Project,
        metadata: ProjectMetadata,
        rootURL: URL?
    ) -> String {
        // 1. Explicit user metadata
        if let explicit = metadata.personalCategory?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            return explicit
        }

        // 2. Derive from folder hierarchy relative to rootURL
        guard let rootURL else {
            let parent = project.folderURL.deletingLastPathComponent().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            return parent.isEmpty ? "Uncategorized" : parent
        }

        let stdProject = project.folderURL.standardizedFileURL.resolvingSymlinksInPath()
        let stdRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath()

        let rootComponents = stdRoot.pathComponents
        let projComponents = stdProject.pathComponents

        guard projComponents.count > rootComponents.count else {
            return "Uncategorized"
        }

        for i in 0..<rootComponents.count {
            if projComponents[i] != rootComponents[i] {
                let parent = stdProject.deletingLastPathComponent().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
                return parent.isEmpty ? "Uncategorized" : parent
            }
        }

        let relative = Array(projComponents[rootComponents.count...])
        // If relative.count <= 1: loose project directly in rootURL
        if relative.count <= 1 {
            return "Uncategorized"
        }

        let firstFolder = relative[0].trimmingCharacters(in: .whitespacesAndNewlines)
        return firstFolder.isEmpty ? "Uncategorized" : firstFolder
    }

    /// Resolves whether a project is a client project and what its client name is.
    nonisolated static func resolveClientStatus(
        project: Project,
        metadata: ProjectMetadata,
        clientBaseURL: URL
    ) -> (isClient: Bool, clientName: String) {
        // 1. Explicit user override: if marked .personal, it's Personal (unless explicitly changed)
        if metadata.projectKind == .personal {
            return (isClient: false, clientName: "")
        }

        // 2. Explicit client name set in metadata
        let trimmedMetadataName = metadata.clientName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedMetadataName.isEmpty {
            return (isClient: true, clientName: trimmedMetadataName)
        }

        // 3. Explicit project kind set to .client
        let isExplicitClient = (metadata.projectKind == .client)

        // 4. Check if project is located inside clientBaseURL
        let insideBase = isProjectInsideBaseURL(project.folderURL, baseURL: clientBaseURL)

        if insideBase {
            let derived = deriveClientNameFromFolder(projectURL: project.folderURL, baseURL: clientBaseURL)
            return (isClient: true, clientName: derived ?? unassignedClientName)
        }

        if isExplicitClient {
            return (isClient: true, clientName: "Direct / Independent")
        }

        return (isClient: false, clientName: "")
    }

    static func buildItems(
        projects: [Project],
        metadataStore: ProjectMetadataStore,
        todoStore: ProjectTodoStore,
        progressStore: ProjectProgressStore,
        clientBaseURL: URL? = nil,
        rootURL: URL? = nil,
        now: Date = Date()
    ) -> (clients: [FocusActionableItem], personal: [FocusActionableItem]) {
        let effectiveBaseURL = clientBaseURL ?? ClientWorkManager.shared.clientWorkBaseURL
        var clientItems: [FocusActionableItem] = []
        var personalItems: [FocusActionableItem] = []

        for project in projects {
            let meta = metadataStore.metadata(for: project)
            let todos = todoStore.todos(for: project)
            let prog = progressStore.progress(for: project)
            let urgency = DeadlineUrgency.calculate(from: meta.targetDeadline, referenceDate: now)

            let item = FocusActionableItem(
                project: project,
                metadata: meta,
                todos: todos,
                progress: prog,
                urgency: urgency,
                clientBaseURL: effectiveBaseURL,
                rootURL: rootURL
            )

            if item.isClient {
                clientItems.append(item)
            } else {
                personalItems.append(item)
            }
        }

        // Sort both by deadline urgency first, then recent modification
        clientItems.sort { lhs, rhs in
            if lhs.urgency != rhs.urgency {
                return lhs.urgency < rhs.urgency
            }
            return lhs.project.latestModification > rhs.project.latestModification
        }

        personalItems.sort { lhs, rhs in
            if lhs.urgency != rhs.urgency {
                return lhs.urgency < rhs.urgency
            }
            return lhs.project.latestModification > rhs.project.latestModification
        }

        return (clientItems, personalItems)
    }

    static func groupByClient(items: [FocusActionableItem], knownClientNames: [String] = []) -> [FocusClientGroup] {
        var grouped = Dictionary(grouping: items, by: { $0.clientName })
        for known in knownClientNames {
            let trimmed = known.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed != unassignedClientName && grouped[trimmed] == nil {
                grouped[trimmed] = []
            }
        }
        return grouped.map { clientName, groupItems in
            FocusClientGroup(
                clientName: clientName,
                items: groupItems.sorted { $0.urgency < $1.urgency }
            )
        }
        .sorted { lhs, rhs in
            let lhsIsUnassigned = (lhs.clientName == unassignedClientName)
            let rhsIsUnassigned = (rhs.clientName == unassignedClientName)
            if lhsIsUnassigned != rhsIsUnassigned {
                return lhsIsUnassigned // Pin "No Client Assigned" to top when present!
            }
            if lhs.mostUrgentDeadline != rhs.mostUrgentDeadline {
                return lhs.mostUrgentDeadline < rhs.mostUrgentDeadline
            }
            if lhs.items.isEmpty != rhs.items.isEmpty {
                return !lhs.items.isEmpty
            }
            return lhs.clientName.localizedCaseInsensitiveCompare(rhs.clientName) == .orderedAscending
        }
    }

    static func groupByPersonalCategory(
        items: [FocusActionableItem],
        knownCategoryNames: [String] = []
    ) -> [FocusCategoryGroup] {
        var grouped = Dictionary(grouping: items, by: { $0.personalCategory })
        for known in knownCategoryNames {
            let trimmed = known.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && grouped[trimmed] == nil {
                grouped[trimmed] = []
            }
        }

        return grouped.map { categoryName, groupItems in
            FocusCategoryGroup(
                categoryName: categoryName,
                items: groupItems.sorted { lhs, rhs in
                    if lhs.urgency != rhs.urgency {
                        return lhs.urgency < rhs.urgency
                    }
                    return lhs.project.latestModification > rhs.project.latestModification
                }
            )
        }
        .sorted { lhs, rhs in
            let lhsIsUncategorized = (lhs.categoryName == "Uncategorized")
            let rhsIsUncategorized = (rhs.categoryName == "Uncategorized")
            if lhsIsUncategorized != rhsIsUncategorized {
                return !lhsIsUncategorized // Put named categories (Portfolio, etc.) first!
            }
            if lhs.mostUrgentDeadline != rhs.mostUrgentDeadline {
                return lhs.mostUrgentDeadline < rhs.mostUrgentDeadline
            }
            if lhs.items.isEmpty != rhs.items.isEmpty {
                return !lhs.items.isEmpty
            }
            return lhs.categoryName.localizedCaseInsensitiveCompare(rhs.categoryName) == .orderedAscending
        }
    }
}
