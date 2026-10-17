import AppKit
import Foundation

struct DailyFocusItem: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    let projectPath: String
    let createdAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        projectPath: String,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.projectPath = projectPath
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    var isCompleted: Bool { completedAt != nil }
}

enum FocusTimerPhase: String, Codable {
    case focus
    case breakTime

    var title: String { self == .focus ? "Focus" : "Break" }
    var nextTitle: String { self == .focus ? "Start break" : "Start focus" }
}

@MainActor
final class DailyFocusStore: ObservableObject {
    @Published private(set) var items: [DailyFocusItem] = []
    @Published var activeItemID: UUID? = nil {
        didSet { defaults.set(activeItemID?.uuidString, forKey: Keys.activeItemID) }
    }
    @Published private(set) var phase: FocusTimerPhase
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var isRunning: Bool
    @Published private(set) var completedFocusSessions: Int
    @Published var focusMinutes: Int {
        didSet {
            defaults.set(focusMinutes, forKey: Keys.focusMinutes)
            if phase == .focus && !isRunning { remainingSeconds = focusMinutes * 60 }
            persistTimer()
        }
    }
    @Published var breakMinutes: Int {
        didSet {
            defaults.set(breakMinutes, forKey: Keys.breakMinutes)
            if phase == .breakTime && !isRunning { remainingSeconds = breakMinutes * 60 }
            persistTimer()
        }
    }
    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) }
    }
    @Published var soundName: String {
        didSet { defaults.set(soundName, forKey: Keys.soundName) }
    }
    @Published var keepsTimerOnTop: Bool {
        didSet { defaults.set(keepsTimerOnTop, forKey: Keys.keepsTimerOnTop) }
    }

    let availableSounds = ["Glass", "Ping", "Pop", "Submarine"]

    private enum Keys {
        static let activeItemID = "dailyFocus.activeItemID"
        static let phase = "dailyFocus.phase"
        static let remainingSeconds = "dailyFocus.remainingSeconds"
        static let isRunning = "dailyFocus.isRunning"
        static let endDate = "dailyFocus.endDate"
        static let focusMinutes = "dailyFocus.focusMinutes"
        static let breakMinutes = "dailyFocus.breakMinutes"
        static let soundEnabled = "dailyFocus.soundEnabled"
        static let soundName = "dailyFocus.soundName"
        static let keepsTimerOnTop = "dailyFocus.keepsTimerOnTop"
        static let completedSessionsDay = "dailyFocus.completedSessionsDay"
        static let completedSessions = "dailyFocus.completedSessions"
    }

    private let defaults = UserDefaults.standard
    private let fileURL: URL
    private var endDate: Date?
    private var timer: Timer?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("Backstage", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("daily-focus.json")

        let savedFocusMinutes = defaults.integer(forKey: Keys.focusMinutes)
        let savedBreakMinutes = defaults.integer(forKey: Keys.breakMinutes)
        let initialFocusMinutes = savedFocusMinutes > 0 ? savedFocusMinutes : 25
        let initialBreakMinutes = savedBreakMinutes > 0 ? savedBreakMinutes : 5
        let initialPhase = FocusTimerPhase(rawValue: defaults.string(forKey: Keys.phase) ?? "") ?? .focus
        let savedRemainingSeconds = defaults.integer(forKey: Keys.remainingSeconds)
        focusMinutes = initialFocusMinutes
        breakMinutes = initialBreakMinutes
        phase = initialPhase
        remainingSeconds = savedRemainingSeconds > 0
            ? savedRemainingSeconds
            : (initialPhase == .focus ? initialFocusMinutes : initialBreakMinutes) * 60
        isRunning = defaults.bool(forKey: Keys.isRunning)
        soundEnabled = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
        soundName = defaults.string(forKey: Keys.soundName) ?? "Glass"
        keepsTimerOnTop = defaults.object(forKey: Keys.keepsTimerOnTop) as? Bool ?? true
        completedFocusSessions = 0
        endDate = defaults.object(forKey: Keys.endDate) as? Date

        if let data = try? Data(contentsOf: fileURL),
           let savedItems = try? JSONDecoder().decode([DailyFocusItem].self, from: data) {
            items = savedItems
        }
        if let rawID = defaults.string(forKey: Keys.activeItemID) {
            activeItemID = UUID(uuidString: rawID)
        }
        restoreSessionCount()
        restoreRunningTimer()
        startTicker()
    }

    deinit { timer?.invalidate() }

    var todayItems: [DailyFocusItem] {
        items.filter { Calendar.current.isDateInToday($0.createdAt) }
            .sorted {
                if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
                return $0.createdAt < $1.createdAt
            }
    }

    var activeItem: DailyFocusItem? {
        guard let activeItemID else { return nil }
        return items.first { $0.id == activeItemID }
    }

    var totalSeconds: Int {
        (phase == .focus ? focusMinutes : breakMinutes) * 60
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return 1 - min(1, max(0, Double(remainingSeconds) / Double(totalSeconds)))
    }

    var timeLabel: String {
        String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    func project(for item: DailyFocusItem, in projects: [Project]) -> Project? {
        projects.first { $0.folderURL.path == item.projectPath }
    }

    func add(_ title: String, project: Project) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = DailyFocusItem(title: trimmed, projectPath: project.folderURL.path)
        items.append(item)
        activeItemID = item.id
        saveItems()
    }

    func toggle(_ item: DailyFocusItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].completedAt = items[index].completedAt == nil ? Date() : nil
        if items[index].completedAt != nil, activeItemID == item.id { activeItemID = nil }
        saveItems()
    }

    func remove(_ item: DailyFocusItem) {
        items.removeAll { $0.id == item.id }
        if activeItemID == item.id { activeItemID = nil }
        saveItems()
    }

    func select(_ item: DailyFocusItem) {
        activeItemID = activeItemID == item.id ? nil : item.id
    }

    func prepareScheduledFocus(project: Project, taskTitles: [String], durationMinutes: Int) {
        let existingTitles = Set(todayItems.filter { $0.projectPath == project.folderURL.path }.map(\.title))
        for title in taskTitles where !existingTitles.contains(title) {
            items.append(DailyFocusItem(title: title, projectPath: project.folderURL.path))
        }
        if let first = todayItems.first(where: {
            $0.projectPath == project.folderURL.path && !$0.isCompleted
        }) {
            activeItemID = first.id
        }
        phase = .focus
        focusMinutes = min(120, max(1, durationMinutes))
        reset()
        saveItems()
    }

    func toggleTimer() {
        isRunning ? pause() : start()
    }

    func start() {
        guard !isRunning else { return }
        if remainingSeconds <= 0 { remainingSeconds = totalSeconds }
        endDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        isRunning = true
        persistTimer()
    }

    func pause() {
        updateRemainingTime()
        isRunning = false
        endDate = nil
        persistTimer()
    }

    func reset() {
        isRunning = false
        endDate = nil
        remainingSeconds = totalSeconds
        persistTimer()
    }

    func skipPhase() {
        isRunning = false
        endDate = nil
        phase = phase == .focus ? .breakTime : .focus
        remainingSeconds = totalSeconds
        persistTimer()
    }

    func previewSound() {
        playCompletionSound()
    }

    private func startTicker() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard isRunning else { return }
        updateRemainingTime()
        if remainingSeconds <= 0 { finishPhase() }
    }

    private func updateRemainingTime() {
        guard let endDate else { return }
        remainingSeconds = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
    }

    private func finishPhase() {
        let finishedPhase = phase
        isRunning = false
        endDate = nil
        if finishedPhase == .focus {
            completedFocusSessions += 1
            saveSessionCount()
        }
        playCompletionSound()
        phase = finishedPhase == .focus ? .breakTime : .focus
        remainingSeconds = totalSeconds
        persistTimer()
    }

    private func playCompletionSound() {
        guard soundEnabled else { return }
        if let sound = NSSound(named: NSSound.Name(soundName)) { sound.play() }
        else { NSSound.beep() }
    }

    private func restoreRunningTimer() {
        guard isRunning, let endDate else {
            isRunning = false
            return
        }
        remainingSeconds = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
        if remainingSeconds == 0 {
            isRunning = false
            self.endDate = nil
            phase = phase == .focus ? .breakTime : .focus
            remainingSeconds = totalSeconds
            persistTimer()
        }
    }

    private func restoreSessionCount() {
        let calendar = Calendar.current
        if let savedDay = defaults.object(forKey: Keys.completedSessionsDay) as? Date,
           calendar.isDateInToday(savedDay) {
            completedFocusSessions = defaults.integer(forKey: Keys.completedSessions)
        } else {
            completedFocusSessions = 0
            saveSessionCount()
        }
    }

    private func saveSessionCount() {
        defaults.set(Date(), forKey: Keys.completedSessionsDay)
        defaults.set(completedFocusSessions, forKey: Keys.completedSessions)
    }

    private func persistTimer() {
        defaults.set(phase.rawValue, forKey: Keys.phase)
        defaults.set(remainingSeconds, forKey: Keys.remainingSeconds)
        defaults.set(isRunning, forKey: Keys.isRunning)
        defaults.set(endDate, forKey: Keys.endDate)
    }

    private func saveItems() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
