import AppKit
import SwiftUI
import EventKit

struct DailyFocusSidebarView: View {
    let showLibrary: () -> Void
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var focus: DailyFocusStore
    @EnvironmentObject private var focusCalendar: FocusCalendarStore
    @EnvironmentObject private var projectTodos: ProjectTodoStore
    @Environment(\.openWindow) private var openWindow
    @State private var newTask = ""
    @State private var projectPath: String?

    private var selectedProject: Project? {
        if let projectPath, let match = store.projects.first(where: { $0.folderURL.path == projectPath }) {
            return match
        }
        return store.selectedProject ?? store.projects.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.divider)

            ScrollView {
                VStack(spacing: 16) {
                    ZStack(alignment: .topTrailing) {
                        FocusTimerCard(compact: true)
                        popOutButton
                            .padding(10)
                    }
                    todayTasks
                    focusPlanning
                    soundControls
                }
                .padding(12)
            }

            Divider().background(Color.divider)
            footer
        }
        .background(Color.sidebarBg)
        .frame(maxHeight: .infinity)
        .onAppear {
            if projectPath == nil { projectPath = store.selectedProject?.folderURL.path }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primaryText)
                    Text(Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.tertiaryText)
                }
                Spacer()
                Button(action: showLibrary) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondaryText)
                        .frame(width: 28, height: 26)
                        .background(Color.hoverBg, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help("Back to library")
            }

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.accent)
                Text(focus.completedFocusSessions == 0
                     ? "Choose one thing and move it forward."
                     : "\(focus.completedFocusSessions) focus \(focus.completedFocusSessions == 1 ? "session" : "sessions") today")
                    .font(.system(size: 10))
                    .foregroundColor(.secondaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 15)
        .padding(.bottom, 11)
    }

    private var todayTasks: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TODAY")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(.tertiaryText)
                Spacer()
                Text("\(focus.todayItems.filter { !$0.isCompleted }.count) left")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.tertiaryText)
            }

            VStack(spacing: 7) {
                Menu {
                    ForEach(store.projects.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }) { project in
                        Button(project.name) { projectPath = project.folderURL.path }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                            .font(.system(size: 9))
                            .foregroundColor(.accent)
                        Text(selectedProject?.name ?? "Choose a project")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondaryText)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundColor(.tertiaryText)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(Color.elevatedBg, in: RoundedRectangle(cornerRadius: 7))
                }
                .menuStyle(.borderlessButton)
                .disabled(store.projects.isEmpty)

                HStack(spacing: 7) {
                    TextField("Next small action…", text: $newTask)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .onSubmit(addTask)
                    Button(action: addTask) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(canAddTask ? .playBtnFg : .tertiaryText)
                            .frame(width: 22, height: 22)
                            .background(canAddTask ? Color.playBtnBg : Color.hoverBg, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAddTask)
                }
                .padding(.leading, 9)
                .padding(.trailing, 5)
                .frame(height: 34)
                .background(Color.surfaceBg, in: RoundedRectangle(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).stroke(Color.subtleBorder) }
            }

            if focus.todayItems.isEmpty {
                Text("Your day is intentionally empty.")
                    .font(.system(size: 10))
                    .foregroundColor(.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 5) {
                    ForEach(focus.todayItems) { item in
                        DailyFocusTaskRow(item: item)
                    }
                }
            }
        }
    }

    private var soundControls: some View {
        HStack(spacing: 8) {
            Button { focus.soundEnabled.toggle() } label: {
                Image(systemName: focus.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 10))
                    .foregroundColor(focus.soundEnabled ? .accent : .tertiaryText)
            }
            .buttonStyle(.plain)
            .help(focus.soundEnabled ? "Mute timer sound" : "Enable timer sound")

            Menu {
                ForEach(focus.availableSounds, id: \.self) { sound in
                    Button {
                        focus.soundName = sound
                        focus.previewSound()
                    } label: {
                        Label(sound, systemImage: focus.soundName == sound ? "checkmark" : "speaker.wave.1")
                    }
                }
            } label: {
                Text(focus.soundEnabled ? focus.soundName : "Sound off")
                    .font(.system(size: 10))
                    .foregroundColor(.secondaryText)
            }
            .menuStyle(.borderlessButton)
            .disabled(!focus.soundEnabled)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var focusPlanning: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PLAN FOCUS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(.tertiaryText)
                Spacer()
                if focusCalendar.hasFullAccess {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 9))
                        .foregroundColor(.tertiaryText)
                    Text("Calendar")
                        .font(.system(size: 9))
                        .foregroundColor(.tertiaryText)
                }
            }

            if focusCalendar.hasFullAccess {
                Button {
                    openWindow(id: "focus-planner")
                    WindowPresenter.showFocusPlanner()
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accent.opacity(0.1))
                                .frame(width: 32, height: 32)
                            Image(systemName: "calendar.day.timeline.left")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Focus planner")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.primaryText)
                            if let event = nextScheduledFocus {
                                Text("Next · \(event.startDate.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                                    .font(.system(size: 9))
                                    .foregroundColor(.tertiaryText)
                            } else {
                                Text("Drag tasks onto your week")
                                    .font(.system(size: 9))
                                    .foregroundColor(.tertiaryText)
                            }
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.tertiaryText)
                    }
                    .padding(9)
                    .background(Color.surfaceBg, in: RoundedRectangle(cornerRadius: 11))
                    .overlay { RoundedRectangle(cornerRadius: 11).stroke(Color.subtleBorder) }
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Connect Apple Calendar to place project sessions on your week and wake the Pomodoro when they begin.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        if focusCalendar.authorizationStatus == .denied || focusCalendar.authorizationStatus == .restricted {
                            openCalendarPrivacySettings()
                        } else {
                            Task { await focusCalendar.requestAccess() }
                        }
                    } label: {
                        Label(
                            focusCalendar.authorizationStatus == .denied ? "Open Calendar Settings" : "Connect Apple Calendar",
                            systemImage: "calendar.badge.plus"
                        )
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.playBtnFg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(Color.playBtnBg, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(focusCalendar.authorizationStatus == .denied ? Color.orange : Color.tertiaryText)
                            .frame(width: 5, height: 5)
                        Text("macOS reports: \(focusCalendar.authorizationLabel)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.tertiaryText)
                        Spacer()
                        Button("Refresh") {
                            Task { await focusCalendar.refreshAuthorization() }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.accent)
                    }

                    if let error = focusCalendar.lastError {
                        Text(error)
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    }
                }
                .padding(10)
                .background(Color.surfaceBg, in: RoundedRectangle(cornerRadius: 11))
                .overlay { RoundedRectangle(cornerRadius: 11).stroke(Color.subtleBorder) }
            }
        }
    }

    private var popOutButton: some View {
        Button {
            openWindow(id: "focus-timer")
            WindowPresenter.showFocusTimer(pinned: focus.keepsTimerOnTop)
        } label: {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondaryText)
                .frame(width: 26, height: 24)
                .background(Color.hoverBg.opacity(0.9), in: Circle())
        }
        .buttonStyle(.plain)
        .help("Pop out timer")
    }

    private var footer: some View {
        HStack {
            Image(systemName: focus.activeItem == nil ? "circle.dotted" : "scope")
                .font(.system(size: 10))
                .foregroundColor(focus.activeItem == nil ? .tertiaryText : .accent)
            Text(focus.activeItem?.title ?? "Select a task to focus")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondaryText)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
    }

    private var canAddTask: Bool {
        selectedProject != nil && !newTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addTask() {
        guard let selectedProject else { return }
        focus.add(newTask, project: selectedProject)
        newTask = ""
    }

    private var nextScheduledFocus: ScheduledFocusEvent? {
        focusCalendar.scheduledEvents.first { $0.endDate > Date() }
    }

    private func openCalendarPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct FocusScheduleSheet: View {
    let project: Project
    let focusTitle: String?
    let day: Date
    let taskTitles: [String]
    @EnvironmentObject private var focusCalendar: FocusCalendarStore
    @Environment(\.dismiss) private var dismiss
    @State private var startDate: Date
    @State private var durationMinutes = 25
    @State private var calendarID: String?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(project: Project, focusTitle: String? = nil, day: Date, taskTitles: [String]) {
        self.project = project
        self.focusTitle = focusTitle
        self.day = day
        self.taskTitles = taskTitles
        _startDate = State(initialValue: Self.suggestedStart(on: day))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.accent.opacity(0.12)).frame(width: 42, height: 42)
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Schedule focus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primaryText)
                    Text(project.name)
                        .font(.system(size: 11))
                        .foregroundColor(.secondaryText)
                    if let focusTitle, !focusTitle.isEmpty {
                        Text(focusTitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.accent)
                            .lineLimit(1)
                    }
                }
            }

            VStack(spacing: 12) {
                scheduleRow("Day") {
                    Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .foregroundColor(.primaryText)
                }
                scheduleRow("Starts") {
                    DatePicker("", selection: $startDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                scheduleRow("Length") {
                    Picker("", selection: $durationMinutes) {
                        Text("25 min").tag(25)
                        Text("50 min").tag(50)
                        Text("90 min").tag(90)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }
                scheduleRow("Calendar") {
                    Picker("", selection: $calendarID) {
                        ForEach(focusCalendar.writableCalendars) { calendar in
                            Text(calendar.title).tag(Optional(calendar.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
            }
            .padding(12)
            .background(Color.surfaceBg, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.subtleBorder) }

            VStack(alignment: .leading, spacing: 7) {
                Text("EVENT DESCRIPTION")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundColor(.tertiaryText)
                if taskTitles.isEmpty {
                    Text("No open project checklist yet. The event will suggest choosing the next small action.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondaryText)
                } else {
                    ForEach(taskTitles, id: \.self) { task in
                        Label(task, systemImage: "square")
                            .font(.system(size: 10))
                            .foregroundColor(.secondaryText)
                            .lineLimit(2)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button {
                    save()
                } label: {
                    if isSaving { ProgressView().controlSize(.small) }
                    else { Text("Add to Calendar") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || calendarID == nil)
            }
        }
        .padding(20)
        .frame(width: 430)
        .background(Color.appBg)
        .onAppear { calendarID = focusCalendar.preferredCalendarID ?? focusCalendar.writableCalendars.first?.id }
    }

    private func scheduleRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondaryText)
            Spacer()
            content()
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await focusCalendar.createEvent(
                    project: project,
                    focusTitle: focusTitle,
                    startDate: startDate,
                    durationMinutes: durationMinutes,
                    taskTitles: taskTitles,
                    calendarID: calendarID
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    private static func suggestedStart(on day: Date) -> Date {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) {
            let now = Date()
            let minutes = calendar.component(.minute, from: now)
            let roundedMinutes = ((minutes / 30) + 1) * 30
            let hourOffset = roundedMinutes / 60
            return calendar.date(bySettingHour: calendar.component(.hour, from: now) + hourOffset,
                                 minute: roundedMinutes % 60, second: 0, of: day) ?? now
        }
        return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day
    }
}

private struct DailyFocusTaskRow: View {
    let item: DailyFocusItem
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var focus: DailyFocusStore
    @State private var hovered = false

    private var project: Project? { focus.project(for: item, in: store.projects) }
    private var isActive: Bool { focus.activeItemID == item.id }

    var body: some View {
        HStack(spacing: 8) {
            Button { focus.toggle(item) } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundColor(item.isCompleted ? .accent : .tertiaryText)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .foregroundColor(item.isCompleted ? .tertiaryText : .primaryText)
                    .strikethrough(item.isCompleted)
                    .lineLimit(2)
                Text(project?.name ?? "Project unavailable")
                    .font(.system(size: 9))
                    .foregroundColor(.tertiaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)

            if hovered && !item.isCompleted {
                Button {
                    if let project {
                        store.selectedProject = project
                        store.openInAbleton(project)
                    }
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 9))
                        .foregroundColor(.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Open in Ableton")
            } else if isActive {
                Circle().fill(Color.accent).frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(isActive ? Color.accent.opacity(0.09) : (hovered ? Color.hoverBg : Color.surfaceBg))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(isActive ? Color.accent.opacity(0.3) : Color.subtleBorder) }
        .contentShape(Rectangle())
        .onTapGesture { if !item.isCompleted { focus.select(item) } }
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Delete", role: .destructive) { focus.remove(item) }
        }
    }
}

struct FocusTimerCard: View {
    let compact: Bool
    @EnvironmentObject private var focus: DailyFocusStore

    var body: some View {
        VStack(spacing: compact ? 11 : 16) {
            ZStack {
                Circle()
                    .stroke(Color.subtleBorder.opacity(0.75), lineWidth: compact ? 7 : 9)
                Circle()
                    .trim(from: 0, to: max(0.002, focus.progress))
                    .stroke(
                        AngularGradient(colors: [.accent.opacity(0.55), .accent, .accent.opacity(0.7)], center: .center),
                        style: StrokeStyle(lineWidth: compact ? 7 : 9, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: focus.progress)

                VStack(spacing: 3) {
                    Text(focus.phase.title.uppercased())
                        .font(.system(size: compact ? 8 : 9, weight: .bold))
                        .tracking(1.1)
                        .foregroundColor(.tertiaryText)
                    Text(focus.timeLabel)
                        .font(.system(size: compact ? 27 : 36, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primaryText)
                    if !compact {
                        Text(focus.activeItem?.title ?? "Ready when you are")
                            .font(.system(size: 10))
                            .foregroundColor(.secondaryText)
                            .lineLimit(1)
                            .frame(maxWidth: 120)
                    }
                }
            }
            .frame(width: compact ? 142 : 190, height: compact ? 142 : 190)

            HStack(spacing: 12) {
                Button(action: focus.reset) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Color.hoverBg, in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondaryText)
                .help("Reset")

                Button(action: focus.toggleTimer) {
                    Image(systemName: focus.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: compact ? 12 : 14, weight: .bold))
                        .offset(x: focus.isRunning ? 0 : 1)
                        .foregroundColor(.playBtnFg)
                        .frame(width: compact ? 40 : 46, height: compact ? 40 : 46)
                        .background(Color.playBtnBg, in: Circle())
                        .shadow(color: Color.black.opacity(0.14), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .help(focus.isRunning ? "Pause" : "Start")

                Button(action: focus.skipPhase) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Color.hoverBg, in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondaryText)
                .help("Skip to \(focus.phase == .focus ? "break" : "focus")")
            }

            if compact {
                HStack(spacing: 6) {
                    ForEach([15, 25, 45], id: \.self) { minutes in
                        Button("\(minutes)") {
                            focus.focusMinutes = minutes
                            if focus.phase != .focus { focus.skipPhase() }
                            focus.reset()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: focus.focusMinutes == minutes ? .bold : .medium, design: .rounded))
                        .foregroundColor(focus.focusMinutes == minutes ? .accent : .tertiaryText)
                        .frame(width: 28, height: 20)
                        .background(focus.focusMinutes == minutes ? Color.accent.opacity(0.1) : Color.clear, in: Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 14 : 20)
        .background(Color.surfaceBg.opacity(compact ? 1 : 0.82), in: RoundedRectangle(cornerRadius: compact ? 18 : 24))
        .overlay { RoundedRectangle(cornerRadius: compact ? 18 : 24).stroke(Color.subtleBorder) }
    }
}

struct FloatingFocusTimerView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var focus: DailyFocusStore

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("goodvibrations")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondaryText)
                    Text(focus.phase == .focus ? "Deep focus" : "Take a breath")
                        .font(.system(size: 9))
                        .foregroundColor(.tertiaryText)
                }
                Spacer()
                Button {
                    focus.keepsTimerOnTop.toggle()
                    WindowPresenter.configureFocusTimer(pinned: focus.keepsTimerOnTop)
                } label: {
                    Image(systemName: focus.keepsTimerOnTop ? "pin.fill" : "pin")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(focus.keepsTimerOnTop ? .accent : .tertiaryText)
                        .frame(width: 26, height: 24)
                        .background(Color.hoverBg, in: Circle())
                }
                .buttonStyle(.plain)
                .help(focus.keepsTimerOnTop ? "Unpin from top" : "Keep on top")
            }

            FocusTimerCard(compact: false)
            floatingChecklist
        }
        .padding(14)
        .frame(width: 292)
        .background(.ultraThinMaterial)
        .background(Color.appBg.opacity(0.72))
        .onAppear { WindowPresenter.configureFocusTimer(pinned: focus.keepsTimerOnTop) }
    }

    private var floatingChecklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Today", systemImage: "checklist")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondaryText)
                Spacer()
                Text("\(focus.todayItems.filter { !$0.isCompleted }.count) left")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.tertiaryText)
            }

            if focus.todayItems.isEmpty {
                Text("Add today’s next action from the Library sidebar.")
                    .font(.system(size: 10))
                    .foregroundColor(.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 7)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(focus.todayItems) { item in
                            DailyFocusTaskRow(item: item)
                        }
                    }
                }
                .frame(maxHeight: 158)
            }
        }
        .padding(10)
        .background(Color.surfaceBg.opacity(0.68), in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.subtleBorder) }
    }
}
