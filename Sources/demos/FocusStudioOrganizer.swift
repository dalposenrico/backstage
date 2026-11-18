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

    var isClient: Bool {
        metadata.projectKind == .client || !(metadata.clientName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var clientName: String {
        let name = metadata.clientName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Direct / Independent" : name
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
            && lhs.urgency == rhs.urgency
            && lhs.metadata.projectKind == rhs.metadata.projectKind
            && lhs.metadata.clientName == rhs.metadata.clientName
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

// MARK: - Organizer Functions

@MainActor
enum FocusStudioOrganizer {
    static func buildItems(
        projects: [Project],
        metadataStore: ProjectMetadataStore,
        todoStore: ProjectTodoStore,
        progressStore: ProjectProgressStore,
        now: Date = Date()
    ) -> (clients: [FocusActionableItem], personal: [FocusActionableItem]) {
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
                urgency: urgency
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
            if !trimmed.isEmpty && grouped[trimmed] == nil {
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
            if lhs.mostUrgentDeadline != rhs.mostUrgentDeadline {
                return lhs.mostUrgentDeadline < rhs.mostUrgentDeadline
            }
            if lhs.items.isEmpty != rhs.items.isEmpty {
                return !lhs.items.isEmpty
            }
            return lhs.clientName.localizedCaseInsensitiveCompare(rhs.clientName) == .orderedAscending
        }
    }
}
