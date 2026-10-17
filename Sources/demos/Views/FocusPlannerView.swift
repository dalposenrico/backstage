import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let goodvibrationsFocusPlannerItem = UTType(exportedAs: "com.enricodalpos.goodvibrationshq.focus-planner-item")
}

struct FocusPlannerDragItem: Codable, Hashable, Transferable {
    enum Kind: String, Codable { case task, event }

    let kind: Kind
    let title: String
    let projectPath: String
    let projectName: String
    let eventIdentifier: String?

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .goodvibrationsFocusPlannerItem)
    }
}

private struct FocusPlannerTask: Identifiable, Hashable {
    let id: String
    let title: String
    let projectPath: String
    let projectName: String

    var dragItem: FocusPlannerDragItem {
        FocusPlannerDragItem(
            kind: .task,
            title: title,
            projectPath: projectPath,
            projectName: projectName,
            eventIdentifier: nil
        )
    }
}

private struct FocusPlannerScheduleRequest: Identifiable {
    let id = UUID()
    let task: FocusPlannerDragItem
    let day: Date
}

struct FocusPlannerView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var focus: DailyFocusStore
    @EnvironmentObject private var focusCalendar: FocusCalendarStore
    @EnvironmentObject private var projectTodos: ProjectTodoStore
    @State private var weekOffset = 0
    @State private var selectedProjectPath: String?
    @State private var newTask = ""
    @State private var scheduleRequest: FocusPlannerScheduleRequest?
    @State private var errorMessage: String?

    private var selectedProject: Project? {
        if let selectedProjectPath,
           let project = store.projects.first(where: { $0.folderURL.path == selectedProjectPath }) {
            return project
        }
        return store.selectedProject ?? store.projects.first
    }

    private var weekStart: Date {
        let calendar = Calendar.current
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .weekOfYear, value: weekOffset, to: currentWeek) ?? currentWeek
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        VStack(spacing: 0) {
            plannerHeader
            Divider().background(Color.divider)

            HStack(spacing: 0) {
                taskPanel
                    .frame(width: 254)
                Divider().background(Color.divider)
                weekGrid
            }

            if let errorMessage {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.circle")
                    Text(errorMessage).lineLimit(1)
                    Spacer()
                    Button("Dismiss") { self.errorMessage = nil }
                        .buttonStyle(.plain)
                }
                .font(.system(size: 10))
                .foregroundColor(.orange)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Color.orange.opacity(0.06))
            }
        }
        .background(Color.appBg)
        .frame(minWidth: 980, minHeight: 580)
        .onAppear {
            if selectedProjectPath == nil { selectedProjectPath = store.selectedProject?.folderURL.path }
            Task { await focusCalendar.refresh() }
        }
        .sheet(item: $scheduleRequest) { request in
            if let project = store.projects.first(where: { $0.folderURL.path == request.task.projectPath }) {
                FocusScheduleSheet(
                    project: project,
                    focusTitle: request.task.title,
                    day: request.day,
                    taskTitles: projectTodos.openTodos(for: project).map(\.title)
                )
                .environmentObject(focusCalendar)
            }
        }
    }

    private var plannerHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Focus planner")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primaryText)
                Text("Move the work, not the calendar form.")
                    .font(.system(size: 10))
                    .foregroundColor(.tertiaryText)
            }

            Spacer()

            Button { weekOffset -= 1 } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondaryText)

            Button("Today") { weekOffset = 0 }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondaryText)

            Button { weekOffset += 1 } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondaryText)

            Text(weekRangeLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primaryText)
                .frame(minWidth: 128, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
        .background(Color.sidebarBg.opacity(0.72))
    }

    private var taskPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Unscheduled")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primaryText)
                    Spacer()
                    Text("\(unscheduledTasks.count)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.tertiaryText)
                }

                Menu {
                    ForEach(store.projects.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }) { project in
                        Button(project.name) { selectedProjectPath = project.folderURL.path }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "waveform")
                            .font(.system(size: 9))
                            .foregroundColor(.accent)
                        Text(selectedProject?.name ?? "Choose project")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondaryText)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                            .foregroundColor(.tertiaryText)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(Color.surfaceBg, in: RoundedRectangle(cornerRadius: 7))
                    .overlay { RoundedRectangle(cornerRadius: 7).stroke(Color.subtleBorder) }
                }
                .menuStyle(.borderlessButton)

                HStack(spacing: 6) {
                    TextField("New task…", text: $newTask)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .onSubmit(addTask)
                    Button(action: addTask) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(canAddTask ? .primaryText : .tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAddTask)
                }
                .padding(.horizontal, 9)
                .frame(height: 32)
                .background(Color.surfaceBg, in: RoundedRectangle(cornerRadius: 7))
                .overlay { RoundedRectangle(cornerRadius: 7).stroke(Color.subtleBorder) }
            }
            .padding(14)

            Divider().background(Color.divider)

            ScrollView {
                LazyVStack(spacing: 7) {
                    if unscheduledTasks.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.system(size: 20, weight: .light))
                                .foregroundColor(.tertiaryText)
                            Text("Everything has a place")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondaryText)
                            Text("Add a task or move a scheduled card back from Apple Calendar.")
                                .font(.system(size: 9))
                                .foregroundColor(.tertiaryText)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 32)
                    } else {
                        ForEach(unscheduledTasks) { task in
                            FocusPlannerUnscheduledCard(task: task)
                        }
                    }
                }
                .padding(12)
            }

            HStack(spacing: 6) {
                Image(systemName: "apple.logo")
                Text("Changes sync with Apple Calendar")
            }
            .font(.system(size: 9))
            .foregroundColor(.tertiaryText)
            .padding(.horizontal, 14)
            .frame(height: 34)
        }
        .background(Color.sidebarBg.opacity(0.52))
    }

    private var weekGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(weekDays, id: \.self) { day in
                    FocusPlannerDayColumn(
                        day: day,
                        events: focusCalendar.events(on: day),
                        projectName: { path in store.projects.first { $0.folderURL.path == path }?.name },
                        dropAction: { item in handleDrop(item, on: day) },
                        removeAction: { event in
                            do { try focusCalendar.remove(event) }
                            catch { errorMessage = error.localizedDescription }
                        }
                    )
                    .frame(width: 142)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background(Color.appBg)
    }

    private var unscheduledTasks: [FocusPlannerTask] {
        var result: [FocusPlannerTask] = []
        var seen = Set<String>()
        let scheduledKeys = Set(focusCalendar.scheduledEvents.map {
            "\($0.projectPath)|\(Self.eventDisplayTitle($0.title).lowercased())"
        })

        for item in focus.todayItems where !item.isCompleted {
            guard let project = store.projects.first(where: { $0.folderURL.path == item.projectPath }) else { continue }
            let key = "\(item.projectPath)|\(item.title.lowercased())"
            guard seen.insert(key).inserted, !scheduledKeys.contains(key) else { continue }
            result.append(FocusPlannerTask(id: "daily-\(item.id)", title: item.title,
                                           projectPath: item.projectPath, projectName: project.name))
        }

        if let selectedProject {
            for todo in projectTodos.openTodos(for: selectedProject) {
                let key = "\(selectedProject.folderURL.path)|\(todo.title.lowercased())"
                guard seen.insert(key).inserted, !scheduledKeys.contains(key) else { continue }
                result.append(FocusPlannerTask(id: "todo-\(todo.id)", title: todo.title,
                                               projectPath: selectedProject.folderURL.path,
                                               projectName: selectedProject.name))
            }
        }
        return result
    }

    private var weekRangeLabel: String {
        guard let last = weekDays.last else { return "" }
        if Calendar.current.isDate(weekStart, equalTo: last, toGranularity: .month) {
            return "\(weekStart.formatted(.dateTime.month(.wide).day()))–\(last.formatted(.dateTime.day()))"
        }
        return "\(weekStart.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var canAddTask: Bool {
        selectedProject != nil && !newTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addTask() {
        guard let selectedProject else { return }
        focus.add(newTask, project: selectedProject)
        newTask = ""
    }

    private func handleDrop(_ item: FocusPlannerDragItem, on day: Date) {
        switch item.kind {
        case .task:
            scheduleRequest = FocusPlannerScheduleRequest(task: item, day: day)
        case .event:
            guard let eventIdentifier = item.eventIdentifier,
                  let event = focusCalendar.scheduledEvents.first(where: { $0.eventIdentifier == eventIdentifier }) else { return }
            Task {
                do { try await focusCalendar.move(event, to: day) }
                catch { errorMessage = error.localizedDescription }
            }
        }
    }

    fileprivate static func eventDisplayTitle(_ title: String) -> String {
        title.replacingOccurrences(of: "Focus · ", with: "")
    }
}

private struct FocusPlannerUnscheduledCard: View {
    let task: FocusPlannerTask

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "drag.handle")
                    .font(.system(size: 10))
                    .foregroundColor(.tertiaryText)
                    .padding(.top, 1)
                Text(task.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primaryText)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
            Label(task.projectName, systemImage: "waveform")
                .font(.system(size: 9))
                .foregroundColor(.tertiaryText)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceBg, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.subtleBorder) }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .draggable(task.dragItem) {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Text(task.projectName).font(.system(size: 9)).foregroundColor(.secondary)
            }
            .padding(9)
            .frame(width: 180, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct FocusPlannerDayColumn: View {
    let day: Date
    let events: [ScheduledFocusEvent]
    let projectName: (String) -> String?
    let dropAction: (FocusPlannerDragItem) -> Void
    let removeAction: (ScheduledFocusEvent) -> Void
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundColor(.tertiaryText)
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 18, weight: Calendar.current.isDateInToday(day) ? .semibold : .medium, design: .rounded))
                    .foregroundColor(Calendar.current.isDateInToday(day) ? .playBtnFg : .primaryText)
                    .frame(width: 31, height: 31)
                    .background(Calendar.current.isDateInToday(day) ? Color.playBtnBg : Color.clear, in: Circle())
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)

            Divider().background(Color.divider)

            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(events) { event in
                        FocusPlannerEventCard(
                            event: event,
                            projectName: projectName(event.projectPath) ?? "Project unavailable",
                            removeAction: { removeAction(event) }
                        )
                    }

                    if events.isEmpty {
                        VStack(spacing: 7) {
                            Image(systemName: isTargeted ? "arrow.down.circle.fill" : "plus.circle")
                                .font(.system(size: 17, weight: .light))
                                .foregroundColor(isTargeted ? .accent : .tertiaryText.opacity(0.6))
                            Text(isTargeted ? "Drop to schedule" : "Drop a task")
                                .font(.system(size: 9, weight: isTargeted ? .semibold : .regular))
                                .foregroundColor(isTargeted ? .accent : .tertiaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 26)
                    }
                }
                .padding(8)
            }
        }
        .background(isTargeted ? Color.accent.opacity(0.055) : Color.clear)
        .overlay(alignment: .leading) { Rectangle().fill(Color.divider).frame(width: 1) }
        .contentShape(Rectangle())
        .dropDestination(for: FocusPlannerDragItem.self) { items, _ in
            guard let item = items.first else { return false }
            dropAction(item)
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

private struct FocusPlannerEventCard: View {
    let event: ScheduledFocusEvent
    let projectName: String
    let removeAction: () -> Void

    private var dragItem: FocusPlannerDragItem {
        FocusPlannerDragItem(
            kind: .event,
            title: FocusPlannerView.eventDisplayTitle(event.title),
            projectPath: event.projectPath,
            projectName: projectName,
            eventIdentifier: event.eventIdentifier
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(FocusPlannerView.eventDisplayTitle(event.title))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.primaryText)
                .lineLimit(3)

            HStack(spacing: 5) {
                Text(event.startDate.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(.accent)
                Text("·")
                    .foregroundColor(.tertiaryText)
                Text("\(event.durationMinutes)m")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.tertiaryText)
            }

            Label(projectName, systemImage: "waveform")
                .font(.system(size: 8))
                .foregroundColor(.tertiaryText)
                .lineLimit(1)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accent.opacity(0.72))
                .frame(width: 3)
                .padding(.vertical, 5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .draggable(dragItem)
        .contextMenu {
            Button("Remove from Calendar", role: .destructive, action: removeAction)
        }
    }
}
