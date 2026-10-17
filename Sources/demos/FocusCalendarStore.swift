import AppKit
import EventKit
import Foundation

struct FocusCalendarChoice: Identifiable, Hashable {
    let id: String
    let title: String
    let sourceTitle: String
}

struct ScheduledFocusEvent: Identifiable, Equatable {
    let eventIdentifier: String
    let title: String
    let projectPath: String
    let startDate: Date
    let endDate: Date
    let calendarTitle: String

    var id: String { "\(eventIdentifier)|\(startDate.timeIntervalSince1970)" }
    var durationMinutes: Int { max(1, Int(endDate.timeIntervalSince(startDate) / 60)) }
}

@MainActor
final class FocusCalendarStore: ObservableObject {
    @Published private(set) var authorizationStatus: EKAuthorizationStatus
    @Published private(set) var writableCalendars: [FocusCalendarChoice] = []
    @Published private(set) var scheduledEvents: [ScheduledFocusEvent] = []
    @Published private(set) var dueEvent: ScheduledFocusEvent?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false
    @Published var preferredCalendarID: String? {
        didSet { defaults.set(preferredCalendarID, forKey: Keys.preferredCalendarID) }
    }

    private enum Keys {
        static let preferredCalendarID = "focusCalendar.preferredCalendarID"
        static let triggeredEventIDs = "focusCalendar.triggeredEventIDs"
    }

    /// EventKit queries are synchronous IPC into calaccessd. The 15-second timer
    /// exists to start scheduled sessions promptly, so it re-reads the calendar
    /// only occasionally and relies on change notifications in between.
    private static let eventKitRefreshInterval: TimeInterval = 300

    private let eventStore = EKEventStore()
    private let defaults = UserDefaults.standard
    private var lastEventKitRefresh: Date?
    private var refreshTimer: Timer?
    private var eventStoreObserver: NSObjectProtocol?
    private var appActivationObserver: NSObjectProtocol?
    private var triggeredEventIDs: Set<String>

    init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        preferredCalendarID = defaults.string(forKey: Keys.preferredCalendarID)
        triggeredEventIDs = Set(defaults.stringArray(forKey: Keys.triggeredEventIDs) ?? [])

        eventStoreObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh(force: true) }
        }

        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refreshAuthorization() }
        }

        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
                self?.checkForDueEvent()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer

        if hasFullAccess {
            Task { await refresh() }
        }
    }

    deinit {
        refreshTimer?.invalidate()
        if let eventStoreObserver { NotificationCenter.default.removeObserver(eventStoreObserver) }
        if let appActivationObserver { NotificationCenter.default.removeObserver(appActivationObserver) }
    }

    var hasFullAccess: Bool { authorizationStatus == .fullAccess }

    var authorizationLabel: String {
        switch authorizationStatus {
        case .notDetermined: return "Not requested"
        case .restricted: return "Restricted by macOS"
        case .denied: return "Denied"
        case .fullAccess: return "Full Access"
        case .writeOnly: return "Add Events Only"
        @unknown default: return "Unknown"
        }
    }

    func refreshAuthorization() async {
        eventStore.reset()
        updateAuthorizationStatus()
        if hasFullAccess {
            lastError = nil
            await refresh(force: true)
        }
    }

    private func updateAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard authorizationStatus != status else { return }
        authorizationStatus = status
    }

    func requestAccess() async {
        lastError = nil
        eventStore.reset()
        updateAuthorizationStatus()
        if hasFullAccess {
            await refresh(force: true)
            return
        }
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            updateAuthorizationStatus()
            guard granted, hasFullAccess else {
                lastError = "Full Calendar access is needed to schedule and watch focus sessions."
                return
            }
            await refresh(force: true)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refresh(force: Bool = false) async {
        updateAuthorizationStatus()
        guard hasFullAccess, !isRefreshing else { return }

        if !force,
           let lastEventKitRefresh,
           Date().timeIntervalSince(lastEventKitRefresh) < Self.eventKitRefreshInterval {
            checkForDueEvent()
            return
        }

        lastError = nil
        isRefreshing = true
        defer { isRefreshing = false }

        let calendars = eventStore.calendars(for: .event).filter { $0.allowsContentModifications }
        let choices = calendars
            .map { FocusCalendarChoice(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source.title) }
            .sorted {
                if $0.title == $1.title { return $0.sourceTitle < $1.sourceTitle }
                return $0.title.localizedCompare($1.title) == .orderedAscending
            }
        // Reassigning an unchanged @Published value invalidates every observing
        // view, so only publish when the calendar contents actually differ.
        if writableCalendars != choices { writableCalendars = choices }

        if preferredCalendarID.flatMap({ id in calendars.first { $0.calendarIdentifier == id } }) == nil {
            let fallback = eventStore.defaultCalendarForNewEvents?.calendarIdentifier
                ?? calendars.first?.calendarIdentifier
            if preferredCalendarID != fallback { preferredCalendarID = fallback }
        }

        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now
        let end = calendar.date(byAdding: .day, value: 14, to: start) ?? now.addingTimeInterval(14 * 86_400)
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate)
            .compactMap(Self.scheduledFocusEvent)
            .sorted { $0.startDate < $1.startDate }
        if scheduledEvents != events { scheduledEvents = events }

        lastEventKitRefresh = Date()
        pruneTriggeredEvents()
        checkForDueEvent()
    }

    func events(on day: Date) -> [ScheduledFocusEvent] {
        scheduledEvents.filter { Calendar.current.isDate($0.startDate, inSameDayAs: day) }
    }

    func createEvent(
        project: Project,
        focusTitle: String? = nil,
        startDate: Date,
        durationMinutes: Int,
        taskTitles: [String],
        calendarID: String?
    ) async throws {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        guard hasFullAccess else {
            throw FocusCalendarError.accessRequired
        }
        let targetCalendar = calendarID.flatMap(eventStore.calendar(withIdentifier:))
            ?? preferredCalendarID.flatMap(eventStore.calendar(withIdentifier:))
            ?? eventStore.defaultCalendarForNewEvents
        guard let targetCalendar, targetCalendar.allowsContentModifications else {
            throw FocusCalendarError.noWritableCalendar
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = targetCalendar
        let trimmedFocusTitle = focusTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        event.title = "Focus · \((trimmedFocusTitle?.isEmpty == false ? trimmedFocusTitle : nil) ?? project.name)"
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(TimeInterval(max(1, durationMinutes) * 60))
        event.notes = FocusCalendarEventContent.notes(projectName: project.name, taskTitles: taskTitles)
        event.url = FocusCalendarEventContent.url(projectPath: project.folderURL.path)
        event.addAlarm(EKAlarm(relativeOffset: 0))
        try eventStore.save(event, span: .thisEvent, commit: true)
        preferredCalendarID = targetCalendar.calendarIdentifier
        await refresh(force: true)
    }

    func move(_ scheduledEvent: ScheduledFocusEvent, to day: Date) async throws {
        guard let event = eventStore.event(withIdentifier: scheduledEvent.eventIdentifier) else {
            throw FocusCalendarError.eventUnavailable
        }
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute, .second], from: event.startDate)
        var dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        dayComponents.hour = time.hour
        dayComponents.minute = time.minute
        dayComponents.second = time.second
        guard let newStart = calendar.date(from: dayComponents) else {
            throw FocusCalendarError.eventUnavailable
        }
        let duration = event.endDate.timeIntervalSince(event.startDate)
        event.startDate = newStart
        event.endDate = newStart.addingTimeInterval(duration)
        try eventStore.save(event, span: .thisEvent, commit: true)
        await refresh(force: true)
    }

    func remove(_ scheduledEvent: ScheduledFocusEvent) throws {
        guard let event = eventStore.event(withIdentifier: scheduledEvent.eventIdentifier) else { return }
        try eventStore.remove(event, span: .thisEvent, commit: true)
        scheduledEvents.removeAll { $0.id == scheduledEvent.id }
    }

    func checkForDueEvent() {
        guard dueEvent == nil else { return }
        let now = Date()
        guard let event = scheduledEvents.first(where: {
            $0.startDate <= now && $0.endDate > now && !triggeredEventIDs.contains($0.id)
        }) else { return }
        triggeredEventIDs.insert(event.id)
        defaults.set(Array(triggeredEventIDs), forKey: Keys.triggeredEventIDs)
        dueEvent = event
        if !NSApp.windows.contains(where: { $0.title != "Focus Timer" && !$0.isMiniaturized }) {
            NSWorkspace.shared.open(FocusCalendarEventContent.wakeURL(for: event))
        }
    }

    func acknowledgeDueEvent() {
        dueEvent = nil
    }

    private func pruneTriggeredEvents() {
        let activeIDs = Set(scheduledEvents.filter { $0.endDate > Date().addingTimeInterval(-86_400) }.map(\.id))
        let previous = triggeredEventIDs
        triggeredEventIDs.formIntersection(activeIDs)
        guard triggeredEventIDs != previous else { return }
        defaults.set(Array(triggeredEventIDs), forKey: Keys.triggeredEventIDs)
    }

    private static func scheduledFocusEvent(from event: EKEvent) -> ScheduledFocusEvent? {
        guard let projectPath = FocusCalendarEventContent.projectPath(from: event.url),
              let eventIdentifier = event.eventIdentifier else { return nil }
        return ScheduledFocusEvent(
            eventIdentifier: eventIdentifier,
            title: event.title ?? "Focus",
            projectPath: projectPath,
            startDate: event.startDate,
            endDate: event.endDate,
            calendarTitle: event.calendar.title
        )
    }

}

enum FocusCalendarEventContent {
    static func url(projectPath: String) -> URL? {
        var components = URLComponents()
        components.scheme = "goodvibrations"
        components.host = "focus"
        components.queryItems = [URLQueryItem(name: "project", value: projectPath)]
        return components.url
    }

    static func wakeURL(for event: ScheduledFocusEvent) -> URL {
        var components = URLComponents()
        components.scheme = "goodvibrations"
        components.host = "focus"
        components.queryItems = [
            URLQueryItem(name: "project", value: event.projectPath),
            URLQueryItem(name: "duration", value: String(event.durationMinutes))
        ]
        return components.url!
    }

    static func projectPath(from url: URL?) -> String? {
        guard let url,
              url.scheme == "goodvibrations",
              url.host == "focus" else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "project" })?.value
    }

    static func durationMinutes(from url: URL) -> Int? {
        let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "duration" })?.value
        return value.flatMap(Int.init)
    }

    static func notes(projectName: String, taskTitles: [String]) -> String {
        let header = "goodvibrations HQ focus session for \(projectName)"
        guard !taskTitles.isEmpty else {
            return "\(header)\n\nOpen the project and choose the next small action."
        }
        let checklist = taskTitles.map { "☐ \($0)" }.joined(separator: "\n")
        return "\(header)\n\nProject checklist\n\(checklist)"
    }
}

private enum FocusCalendarError: LocalizedError {
    case accessRequired
    case noWritableCalendar
    case eventUnavailable

    var errorDescription: String? {
        switch self {
        case .accessRequired: return "Calendar access is required before a focus session can be scheduled."
        case .noWritableCalendar: return "Apple Calendar does not have a writable calendar available."
        case .eventUnavailable: return "That focus event is no longer available in Apple Calendar."
        }
    }
}
