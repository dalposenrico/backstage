import AppKit
import CoreWLAN
import EventKit
import Foundation
@preconcurrency import UserNotifications

struct StudioBooking: Identifiable, Equatable {
    let eventIdentifier: String
    let title: String
    let location: String?
    let startDate: Date
    let endDate: Date

    var id: String { eventIdentifier }
}

@MainActor
final class StudioCheckInAssistant: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var upcomingBookings: [StudioBooking] = []
    @Published private(set) var currentNetworkName: String?
    @Published private(set) var calendarAccessGranted = false
    @Published private(set) var notificationAccessGranted = false
    @Published private(set) var lastError: String?

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            schedulingGeneration &+= 1
            updateRefreshTimer()
            if isEnabled {
                Task { await refresh() }
            } else {
                Task { await cancelAllCheckInNotifications() }
            }
        }
    }
    @Published var calendarMatch: String {
        didSet { UserDefaults.standard.set(calendarMatch, forKey: Keys.calendarMatch) }
    }
    @Published var requiredWiFiName: String {
        didSet { UserDefaults.standard.set(requiredWiFiName, forKey: Keys.wifiName) }
    }
    @Published var portalURLText: String {
        didSet { UserDefaults.standard.set(portalURLText, forKey: Keys.portalURL) }
    }

    private enum Keys {
        static let enabled = "studioCheckIn.enabled"
        static let calendarMatch = "studioCheckIn.calendarMatch"
        static let wifiName = "studioCheckIn.wifiName"
        static let portalURL = "studioCheckIn.portalURL"
        static let completedEventIDs = "studioCheckIn.completedEventIDs"
    }

    private let eventStore = EKEventStore()
    private let notificationCenter = UNUserNotificationCenter.current()
    @Published private var completedEventIDs: Set<String>
    private var refreshTimer: Timer?
    private var schedulingGeneration = 0

    private enum NotificationAction {
        static let category = "STUDIO_CHECK_IN"
        static let openSAE = "OPEN_SAE"
        static let checkedIn = "MARK_CHECKED_IN"
    }

    override init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? false
        calendarMatch = defaults.string(forKey: Keys.calendarMatch) ?? "Studio"
        requiredWiFiName = defaults.string(forKey: Keys.wifiName) ?? "SAE Shared"
        portalURLText = defaults.string(forKey: Keys.portalURL) ?? "https://connect.sae.edu/#personal"
        completedEventIDs = Set(defaults.stringArray(forKey: Keys.completedEventIDs) ?? [])
        super.init()
        notificationCenter.delegate = self
        registerNotificationActions()
        Task {
            await refreshAuthorizationState()
            if isEnabled { await refresh() }
            else { await cancelAllCheckInNotifications() }
        }
    }

    deinit { refreshTimer?.invalidate() }

    /// Nothing here is useful while check-in is off: the timer was querying Wi-Fi
    /// and Calendar every minute even for users who never enabled the feature.
    private func updateRefreshTimer() {
        guard isEnabled else {
            refreshTimer?.invalidate()
            refreshTimer = nil
            return
        }
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    var isOnRequiredWiFi: Bool {
        guard let currentNetworkName else { return false }
        return currentNetworkName.caseInsensitiveCompare(requiredWiFiName) == .orderedSame
    }

    var nextRelevantBooking: StudioBooking? {
        let now = Date()
        return upcomingBookings.first { $0.endDate.addingTimeInterval(30 * 60) > now }
    }

    func enable() async {
        lastError = nil
        do {
            calendarAccessGranted = try await eventStore.requestFullAccessToEvents()
            notificationAccessGranted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            isEnabled = calendarAccessGranted && notificationAccessGranted
            if !calendarAccessGranted { lastError = "Calendar access is needed to find studio bookings." }
            else if !notificationAccessGranted { lastError = "Notification access is needed for check-in reminders." }
            await refresh()
        } catch {
            lastError = error.localizedDescription
            isEnabled = false
        }
    }

    func refresh() async {
        guard isEnabled else { return }
        await refreshAuthorizationState()
        let networkName = CWWiFiClient.shared().interface()?.ssid()
        if currentNetworkName != networkName { currentNetworkName = networkName }
        guard calendarAccessGranted else { return }

        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(byAdding: .hour, value: -1, to: now) ?? now
        let end = calendar.date(byAdding: .day, value: 14, to: now) ?? now
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let needle = calendarMatch.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookings = eventStore.events(matching: predicate)
            .filter { event in
                !needle.isEmpty && [event.title, event.location]
                    .compactMap { $0 }
                    .contains { $0.localizedCaseInsensitiveContains(needle) }
            }
            .map {
                StudioBooking(eventIdentifier: $0.eventIdentifier, title: $0.title,
                              location: $0.location, startDate: $0.startDate, endDate: $0.endDate)
            }
            .sorted { $0.startDate < $1.startDate }
        if upcomingBookings != bookings { upcomingBookings = bookings }

        pruneCompletedEvents()
        await scheduleReminders()
    }

    func openPortal() {
        guard let url = URL(string: portalURLText) else {
            lastError = "The SAE portal address is not valid."
            return
        }
        NSWorkspace.shared.open(url)
    }

    func markCheckedIn(_ booking: StudioBooking) {
        completedEventIDs.insert(booking.eventIdentifier)
        saveCompletedEvents()
        schedulingGeneration &+= 1
        Task { await cancelNotifications(for: booking.eventIdentifier) }
    }

    func isCompleted(_ booking: StudioBooking) -> Bool {
        completedEventIDs.contains(booking.eventIdentifier)
    }

    private func refreshAuthorizationState() async {
        let calendarGranted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        if calendarAccessGranted != calendarGranted { calendarAccessGranted = calendarGranted }
        let settings = await notificationCenter.notificationSettings()
        let notificationsGranted = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        if notificationAccessGranted != notificationsGranted { notificationAccessGranted = notificationsGranted }
    }

    private func scheduleReminders() async {
        let generation = schedulingGeneration
        let now = Date()
        for booking in upcomingBookings where !isCompleted(booking) {
            let reminderOffsets = Array(stride(from: -10, through: 14, by: 2)) + [15]
            let reminderDates = reminderOffsets.map {
                booking.startDate.addingTimeInterval(TimeInterval($0 * 60))
            }
            for (index, date) in reminderDates.enumerated() where date > now {
                guard isEnabled, generation == schedulingGeneration, !isCompleted(booking) else { return }
                let identifier = notificationID(for: booking, index: index)
                let content = UNMutableNotificationContent()
                content.title = isOnRequiredWiFi ? "✅ SAE studio check-in ready" : "⏰ SAE studio check-in"
                content.subtitle = booking.title
                content.body = isOnRequiredWiFi
                    ? "You're on \(requiredWiFiName). Open SAE and check in for \(booking.title)."
                    : "Connect to \(requiredWiFiName), then open SAE and check in for \(booking.title)."
                content.sound = .default
                content.categoryIdentifier = NotificationAction.category
                content.userInfo = ["bookingID": booking.eventIdentifier]
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                let request = UNNotificationRequest(identifier: identifier, content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
                try? await notificationCenter.add(request)
                if !isEnabled || generation != schedulingGeneration || isCompleted(booking) {
                    notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
                    notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
                    return
                }
            }
        }
    }

    private func notificationID(for booking: StudioBooking, index: Int) -> String {
        "studio-check-in.\(booking.eventIdentifier).\(index)"
    }

    private func registerNotificationActions() {
        let open = UNNotificationAction(identifier: NotificationAction.openSAE,
                                        title: "Open SAE", options: [.foreground])
        let checkedIn = UNNotificationAction(identifier: NotificationAction.checkedIn,
                                             title: "I'm checked in")
        let category = UNNotificationCategory(identifier: NotificationAction.category,
                                              actions: [open, checkedIn], intentIdentifiers: [])
        notificationCenter.setNotificationCategories([category])
    }

    private func cancelNotifications(for bookingID: String) async {
        let prefix = "studio-check-in.\(bookingID)."
        await removeNotifications(matching: { $0.hasPrefix(prefix) })
    }

    private func cancelAllCheckInNotifications() async {
        await removeNotifications(matching: { $0.hasPrefix("studio-check-in.") })
    }

    private func removeNotifications(matching predicate: @escaping (String) -> Bool) async {
        let center = notificationCenter
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                let ids = requests.map(\.identifier).filter(predicate)
                center.removePendingNotificationRequests(withIdentifiers: ids)
                continuation.resume()
            }
        }
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                let ids = notifications.map { $0.request.identifier }.filter(predicate)
                center.removeDeliveredNotifications(withIdentifiers: ids)
                continuation.resume()
            }
        }
    }

    private func pruneCompletedEvents() {
        let liveIDs = Set(upcomingBookings.map(\.eventIdentifier))
        let previous = completedEventIDs
        completedEventIDs.formIntersection(liveIDs)
        guard completedEventIDs != previous else { return }
        saveCompletedEvents()
    }

    private func saveCompletedEvents() {
        UserDefaults.standard.set(Array(completedEventIDs), forKey: Keys.completedEventIDs)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let bookingID = response.notification.request.content.userInfo["bookingID"] as? String
        if response.actionIdentifier == NotificationAction.checkedIn, let bookingID {
            await MainActor.run {
                if let booking = self.upcomingBookings.first(where: { $0.eventIdentifier == bookingID }) {
                    self.markCheckedIn(booking)
                }
            }
        } else if response.actionIdentifier == NotificationAction.openSAE ||
                    response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            await MainActor.run { self.openPortal() }
        }
    }
}
