import SwiftUI

struct ProductionChecklistView: View {
    let project: Project
    @EnvironmentObject private var workflow: StudioWorkflowStore
    @EnvironmentObject private var progressStore: ProjectProgressStore
    @Environment(\.openWindow) private var openWindow
    @State private var selectedStage: ProjectStage = .spark
    @State private var reflectionsExpanded = false
    @State private var ideasExpanded = false

    private var currentStage: ProjectStage { progressStore.progress(for: project).stage }
    private var stageItems: [StudioWorkflowItem] { workflow.items(for: selectedStage) }
    private var essentialChecks: [StudioWorkflowItem] {
        stageItems.filter { $0.importance == .core && $0.kind == .checklist }
    }
    private var essentialReflections: [StudioWorkflowItem] {
        stageItems.filter { $0.importance == .core && $0.kind == .reflection }
    }
    private var optionalItems: [StudioWorkflowItem] {
        stageItems.filter { $0.importance == .optional || $0.kind == .guidance }
    }
    private var progress: (resolved: Int, total: Int) {
        workflow.coreProgress(for: project, stage: selectedStage)
    }
    private var remaining: Int { max(0, progress.total - progress.resolved) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Label("PRODUCTION CHECKLIST", systemImage: "checklist")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.7)
                        .foregroundColor(.tertiaryText)
                    Text("Keep the next production decision in sight.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondaryText)
                }
                Spacer()
                Button {
                    openWindow(id: "studio-companion")
                    WindowPresenter.showWorkflowEditor()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12))
                        .foregroundColor(.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Edit checklist template")
            }

            phasePath

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(selectedStage.title)
                                .font(.system(size: 17, weight: .semibold))
                            if selectedStage == currentStage {
                                Text("CURRENT")
                                    .font(.system(size: 8, weight: .bold))
                                    .tracking(0.5)
                                    .foregroundColor(selectedStage.companionColor)
                            }
                        }
                        Text(progressSummary)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(remaining == 0 ? selectedStage.companionColor : .secondaryText)
                    }
                    Spacer()
                    Text("\(progress.resolved)/\(progress.total)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondaryText)
                }

                ProgressView(value: progress.total == 0 ? 0 : Double(progress.resolved), total: Double(max(progress.total, 1)))
                    .tint(selectedStage.companionColor)
            }

            if !essentialChecks.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    sectionLabel("ESSENTIAL CHECKS")
                    ForEach(essentialChecks) { item in
                        ChecklistItemView(item: item, project: project)
                    }
                }
            }

            if !essentialReflections.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    expandableSectionHeader(
                        "REFLECTIONS",
                        count: essentialReflections.count,
                        resolved: essentialReflections.filter { workflow.isResolved($0, for: project) }.count,
                        isExpanded: reflectionsExpanded
                    ) {
                        reflectionsExpanded.toggle()
                    }
                    if reflectionsExpanded {
                    VStack(spacing: 7) {
                        ForEach(essentialReflections) { item in
                            ChecklistItemView(item: item, project: project)
                        }
                    }
                    .padding(.top, 7)
                    }
                }
            }

            if !optionalItems.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    expandableSectionHeader(
                        "MORE IDEAS",
                        count: optionalItems.count,
                        resolved: nil,
                        isExpanded: ideasExpanded
                    ) {
                        ideasExpanded.toggle()
                    }
                    if ideasExpanded {
                    VStack(spacing: 7) {
                        ForEach(optionalItems) { item in
                            ChecklistItemView(item: item, project: project)
                        }
                    }
                    .padding(.top, 7)
                    }
                }
            }

            if selectedStage == currentStage && remaining == 0 && progress.total > 0 {
                completionCard
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selectedStage.companionColor.opacity(0.22)))
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .onAppear { selectCurrentStage() }
        .onChange(of: project.id) { _, _ in selectCurrentStage() }
        .onChange(of: currentStage) { _, newStage in
            selectedStage = newStage
            collapseSecondarySections()
        }
        .animation(.easeInOut(duration: 0.18), value: selectedStage)
        .animation(.easeInOut(duration: 0.18), value: remaining)
    }

    private var phasePath: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(Array(ProjectStage.allCases.enumerated()), id: \.element.rawValue) { index, stage in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundColor(.tertiaryText)
                    }
                    Button {
                        selectedStage = stage
                        collapseSecondarySections()
                    } label: {
                        HStack(spacing: 4) {
                            if stage.workflowIndex < currentStage.workflowIndex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            Text(stage.title)
                                .font(.system(size: 9, weight: selectedStage == stage ? .semibold : .medium))
                                .lineLimit(1)
                        }
                        .foregroundColor(selectedStage == stage ? .black : stage == currentStage ? stage.companionColor : .secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(selectedStage == stage ? stage.companionColor : Color.white.opacity(stage == currentStage ? 0.06 : 0.025))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(stage == currentStage && selectedStage != stage ? stage.companionColor.opacity(0.45) : Color.clear))
                    }
                    .buttonStyle(.plain)
                    .help(stage == currentStage ? "Current phase" : "Review \(stage.title)")
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var progressSummary: String {
        if progress.total == 0 { return "No essential items in this phase" }
        if remaining == 0 { return "Essential work complete" }
        return "\(remaining) essential \(remaining == 1 ? "item" : "items") remaining"
    }

    private var completionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(selectedStage.next == nil ? "This version is ready for your decision" : "Phase complete", systemImage: "checkmark.seal.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(selectedStage.companionColor)
            Text(selectedStage.next == nil ? "The checklist is evidence, not a score. Commit when no clear musical problem remains." : "All essential items are resolved. You still choose when the track moves forward.")
                .font(.system(size: 11))
                .foregroundColor(.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let next = selectedStage.next {
                Button("Move to \(next.title)") {
                    progressStore.setStage(next, for: project)
                    selectedStage = next
                    collapseSecondarySections()
                }
                .buttonStyle(.borderedProminent)
                .tint(selectedStage.companionColor)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(selectedStage.companionColor.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.7)
            .foregroundColor(.tertiaryText)
    }

    private func expandableSectionHeader(
        _ title: String,
        count: Int,
        resolved: Int?,
        isExpanded: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.tertiaryText)
                    .frame(width: 9)
                sectionLabel(title)
                Spacer()
                Text(resolved.map { "\($0)/\(count)" } ?? "\(count)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.tertiaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func selectCurrentStage() {
        selectedStage = currentStage
        collapseSecondarySections()
    }

    private func collapseSecondarySections() {
        reflectionsExpanded = false
        ideasExpanded = false
    }
}

private struct ChecklistItemView: View {
    let item: StudioWorkflowItem
    let project: Project
    @EnvironmentObject private var workflow: StudioWorkflowStore
    @EnvironmentObject private var notes: ProjectNotesStore
    @State private var expanded = false
    @State private var addedToNotes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch item.kind {
            case .checklist:
                HStack(alignment: .top, spacing: 10) {
                    Button { workflow.toggle(item, for: project) } label: {
                        Image(systemName: workflow.isResolved(item, for: project) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 17)).foregroundColor(workflow.isResolved(item, for: project) ? item.stage.companionColor : .tertiaryText)
                    }.buttonStyle(.plain)
                    itemText
                }
            case .reflection:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: workflow.isResolved(item, for: project) ? "quote.bubble.fill" : "quote.bubble")
                            .font(.system(size: 15)).foregroundColor(workflow.isResolved(item, for: project) ? item.stage.companionColor : .tertiaryText)
                            .frame(width: 18)
                        itemText
                    }
                    // An auto-growing multiline TextField can enter a recursive layout pass
                    // when it is revealed inside this narrow, scrolling inspector on macOS.
                    // Reflections are intentionally short, so keep the field single-line.
                    TextField("Short answer…", text: workflow.answerBinding(for: item, project: project))
                        .textFieldStyle(.plain)
                        .padding(9)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    HStack {
                        Spacer()
                        Button(addedToNotes ? "Added" : "Add to Project Notes") {
                            let answer = workflow.answer(for: item, project: project)
                            guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            notes.append(StudioWorkflowResolver.notesBlock(stage: item.stage, question: item.title, answer: answer), for: project)
                            addedToNotes = true
                        }
                        .buttonStyle(.borderless).font(.system(size: 10, weight: .medium))
                        .disabled(workflow.answer(for: item, project: project).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            case .guidance:
                DisclosureGroup(isExpanded: $expanded) { detailText.padding(.top, 5) } label: {
                    Label(item.title, systemImage: "lightbulb")
                        .font(.system(size: 13, weight: .medium)).foregroundColor(.primaryText)
                }
                .tint(.secondaryText)
            }
        }
        .padding(10)
        .background(Color.white.opacity(item.importance == .core ? 0.035 : 0.02))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .onChange(of: project.id) { _, _ in addedToNotes = false }
        .onChange(of: workflow.answer(for: item, project: project)) { _, _ in addedToNotes = false }
    }

    private var itemText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { expanded.toggle() } label: {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primaryText)
                        .multilineTextAlignment(.leading)
                    if !item.detail.isEmpty {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundColor(.tertiaryText)
                    }
                }
            }
            .buttonStyle(.plain)
            if expanded && !item.detail.isEmpty { detailText }
        }
    }

    private var detailText: some View {
        Text(item.detail).font(.system(size: 11)).foregroundColor(.secondaryText).fixedSize(horizontal: false, vertical: true)
    }
}

struct WorkflowEditorWindow: View {
    @EnvironmentObject private var workflow: StudioWorkflowStore
    @State private var selectedStage: ProjectStage = .spark
    @State private var confirmRestoreStage = false
    @State private var confirmRestoreAll = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workflow Editor").font(.system(size: 17, weight: .semibold))
                    Text("Customize the Production Checklist used by every project.")
                        .font(.system(size: 11)).foregroundColor(.secondaryText)
                }
                Spacer()
                Menu {
                    Button("Restore \(selectedStage.title)") { confirmRestoreStage = true }
                    Button("Restore Entire Workflow") { confirmRestoreAll = true }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .menuStyle(.borderlessButton)
                .help("Restore built-in workflow")
            }
            .padding(16)

            Divider().background(Color.divider)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ProjectStage.allCases, id: \.rawValue) { stage in
                        Button { selectedStage = stage } label: {
                            Text(stage.title)
                                .font(.system(size: 11, weight: selectedStage == stage ? .semibold : .regular))
                                .foregroundColor(selectedStage == stage ? .black : .secondaryText)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(selectedStage == stage ? stage.companionColor : Color.clear)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }

            Divider().background(Color.divider)
            WorkflowEditorView(stage: selectedStage)
        }
        .background(Color.appBg)
        .confirmationDialog("Restore \(selectedStage.title) workflow?", isPresented: $confirmRestoreStage) {
            Button("Restore Stage", role: .destructive) { workflow.restoreStage(selectedStage) }
        } message: { Text("This removes personal items and edits in this stage. Project answers and completion remain stored.") }
        .confirmationDialog("Restore the full built-in workflow?", isPresented: $confirmRestoreAll) {
            Button("Restore All", role: .destructive) { workflow.restoreAll() }
        } message: { Text("This removes all template edits and personal workflow items. Project answers and completion remain stored.") }
    }
}

private struct WorkflowEditorView: View {
    let stage: ProjectStage
    @EnvironmentObject private var workflow: StudioWorkflowStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Changes apply to every project. Answers and checkmarks stay project-specific.")
                    .font(.system(size: 11)).foregroundColor(.secondaryText)
                Spacer()
                Button { workflow.addCustomItem(stage: stage) } label: { Label("Add Item", systemImage: "plus") }
                    .buttonStyle(.bordered).controlSize(.small)
            }.padding(16)
            Divider().background(Color.divider)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(workflow.items(for: stage)) { item in
                        WorkflowEditorRow(item: item)
                            .id("\(item.id)-\(item.order)")
                    }
                    if !workflow.hiddenBuiltIns(for: stage).isEmpty {
                        HStack {
                            Text("HIDDEN BUILT-IN ITEMS")
                                .font(.system(size: 10, weight: .semibold)).tracking(0.7).foregroundColor(.tertiaryText)
                            Spacer()
                        }.padding(.top, 8)
                        ForEach(workflow.hiddenBuiltIns(for: stage)) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.system(size: 12, weight: .medium))
                                    Text(item.kind.title).font(.system(size: 10)).foregroundColor(.secondaryText)
                                }
                                Spacer()
                                Button("Restore") { workflow.restoreItem(item) }.buttonStyle(.bordered).controlSize(.small)
                            }
                            .padding(10).background(Color.white.opacity(0.02)).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }.padding(16)
            }
        }
    }
}

private struct WorkflowEditorRow: View {
    @EnvironmentObject private var workflow: StudioWorkflowStore
    @State private var draft: StudioWorkflowItem
    @State private var confirmDelete = false

    init(item: StudioWorkflowItem) { _draft = State(initialValue: item) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Title", text: $draft.title).font(.system(size: 13, weight: .semibold))
                Picker("", selection: $draft.stage) { ForEach(ProjectStage.allCases, id: \.rawValue) { Text($0.title).tag($0) } }
                    .labelsHidden().frame(width: 95)
                Picker("", selection: $draft.kind) { ForEach(StudioWorkflowItemKind.allCases) { Text($0.title).tag($0) } }
                    .labelsHidden().frame(width: 105)
                Picker("", selection: $draft.importance) { ForEach(StudioWorkflowImportance.allCases) { Text($0.title).tag($0) } }
                    .labelsHidden().frame(width: 90)
            }
            HStack {
                TextField("Section", text: $draft.section).frame(width: 120)
                TextField("Optional guidance", text: $draft.detail, axis: .vertical).lineLimit(1...3)
            }
            HStack(spacing: 12) {
                Button { workflow.moveItem(draft, direction: -1) } label: { Image(systemName: "arrow.up") }.buttonStyle(.plain)
                Button { workflow.moveItem(draft, direction: 1) } label: { Image(systemName: "arrow.down") }.buttonStyle(.plain)
                Spacer()
                if workflow.isBuiltIn(draft) {
                    Button("Restore Item") { workflow.restoreItem(draft) }.buttonStyle(.borderless)
                    Button("Hide", role: .destructive) { workflow.removeItem(draft) }.buttonStyle(.borderless)
                } else {
                    Button("Delete", role: .destructive) { confirmDelete = true }.buttonStyle(.borderless)
                }
            }.font(.system(size: 10, weight: .medium))
        }
        .padding(12).background(Color.white.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 9))
        .onChange(of: draft) { _, value in workflow.updateItem(value) }
        .confirmationDialog("Delete this personal workflow item?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { workflow.removeItem(draft) }
        }
    }
}

extension ProjectStage {
    var companionColor: Color {
        switch self {
        case .spark: return Color(hex: "F39B3D")
        case .structure: return Color(hex: "F4C542")
        case .fullTrack: return Color(hex: "A7E84B")
        case .mix: return Color(hex: "45D6C8")
        case .master: return Color(hex: "5EA8FF")
        case .done: return Color(hex: "C4A3FF")
        }
    }
}
