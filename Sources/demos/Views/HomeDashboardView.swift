import SwiftUI
import AppKit

struct FocusStudioSnapshot {
    let clients: [FocusActionableItem]
    let personal: [FocusActionableItem]
    let clientGroups: [FocusClientGroup]
    let urgentItems: [FocusActionableItem]
    let pendingDeliverablesCount: Int
}

struct HomeDashboardView: View, Equatable {
    var isActive: Bool = true
    let openProject: (Project) -> Void

    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var progressStore: ProjectProgressStore
    @EnvironmentObject private var todoStore: ProjectTodoStore
    @EnvironmentObject private var metadataStore: ProjectMetadataStore

    @ObservedObject private var clientManager = ClientWorkManager.shared

    @AppStorage("focusStudioViewMode") private var viewModeRaw: String = FocusStudioViewMode.split.rawValue
    @State private var searchQuery: String = ""
    @State private var expandedProjectIDs: Set<Project.ID> = []
    @State private var collapsedClientNames: Set<String> = []

    // Client Creation & Folder Management State
    @State private var showingCreateClientAlert = false
    @State private var newClientNameDraft = ""
    @State private var showingRenameFolderAlert = false
    @State private var renameFolderNameDraft = ""

    // Move Project to Client State
    @State private var projectToMove: Project? = nil
    @State private var statusFeedbackMessage: String? = nil

    static func == (lhs: HomeDashboardView, rhs: HomeDashboardView) -> Bool {
        lhs.isActive == rhs.isActive && !lhs.isActive
    }

    private var viewMode: FocusStudioViewMode {
        FocusStudioViewMode(rawValue: viewModeRaw) ?? .split
    }

    private var allVisibleProjects: [Project] {
        store.visibleProjects
    }

    private var snapshot: FocusStudioSnapshot {
        let (rawClients, rawPersonal) = FocusStudioOrganizer.buildItems(
            projects: allVisibleProjects,
            metadataStore: metadataStore,
            todoStore: todoStore,
            progressStore: progressStore,
            clientBaseURL: clientManager.clientWorkBaseURL
        )

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let clients: [FocusActionableItem]
        let personal: [FocusActionableItem]

        if query.isEmpty {
            clients = rawClients
            personal = rawPersonal
        } else {
            clients = rawClients.filter {
                $0.project.name.lowercased().contains(query)
                    || $0.clientName.lowercased().contains(query)
                    || ($0.metadata.serviceType?.rawValue.lowercased().contains(query) ?? false)
            }
            personal = rawPersonal.filter {
                $0.project.name.lowercased().contains(query)
                    || $0.progress.stage.title.lowercased().contains(query)
                    || $0.progress.nextMove.lowercased().contains(query)
            }
        }

        let groups = FocusStudioOrganizer.groupByClient(
            items: clients,
            knownClientNames: clientManager.discoveredClientNames
        )

        let urgent = (rawClients + rawPersonal)
            .filter { $0.urgency.isUrgent }
            .sorted { $0.urgency < $1.urgency }

        let pendingCount = rawClients.reduce(0) { $0 + ($1.totalDeliverablesCount - $1.completedDeliverablesCount) }

        return FocusStudioSnapshot(
            clients: clients,
            personal: personal,
            clientGroups: groups,
            urgentItems: urgent,
            pendingDeliverablesCount: pendingCount
        )
    }

    var body: some View {
        Group {
            if isActive {
                content
            } else {
                Color.clear
            }
        }
        .sheet(item: $projectToMove) { proj in
            MoveProjectToClientSheet(
                project: proj,
                clientManager: clientManager,
                metadataStore: metadataStore,
                todoStore: todoStore,
                progressStore: progressStore,
                onMoved: { newClient, newPath in
                    projectToMove = nil
                    statusFeedbackMessage = "Moved “\(proj.name)” to client “\(newClient)”"
                    Task { await store.scan() }
                },
                onCancel: {
                    projectToMove = nil
                }
            )
        }
        .alert("Create New Client Folder", isPresented: $showingCreateClientAlert) {
            TextField("Client Name (e.g. Francisco Luz)", text: $newClientNameDraft)
            Button("Cancel", role: .cancel) { newClientNameDraft = "" }
            Button("Create Folder") {
                createClientFolderAction()
            }
        } message: {
            Text("A folder will be created inside:\n\(clientManager.clientWorkBaseURL.path)")
        }
        .alert("Rename Client Work Folder", isPresented: $showingRenameFolderAlert) {
            TextField("Folder Name", text: $renameFolderNameDraft)
            Button("Cancel", role: .cancel) { renameFolderNameDraft = "" }
            Button("Rename") {
                renameBaseFolderAction()
            }
        } message: {
            Text("Enter a new folder name for your client work. If it already exists on disk, it will be renamed safely.")
        }
    }

    private var content: some View {
        let snap = snapshot
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if allVisibleProjects.isEmpty {
                    HomeLibraryStatusView(state: store.libraryLoadPresentation)
                        .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    // Header Bar
                    topHeaderBar(snapshot: snap)

                    // Status Toast Message
                    if let msg = statusFeedbackMessage {
                        statusBanner(message: msg)
                    }

                    // Top Urgency Alert Banner (if urgent deadlines exist)
                    if !snap.urgentItems.isEmpty {
                        urgencyAlertBanner(items: snap.urgentItems)
                    }

                    // Main Work Area (Split or Expanded)
                    mainWorkArea(snapshot: snap)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 48)
            .frame(maxWidth: 1360, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color.appBg)
    }

    // MARK: - Header Bar

    private func topHeaderBar(snapshot snap: FocusStudioSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.accent)
                        Text("Studio Hub")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.primaryText)
                    }
                    Text("Deadlines, client deliverables, and creative momentum organized in one place.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondaryText)
                }

                Spacer()

                // View Mode Switcher: Split | Clients | Personal
                HStack(spacing: 4) {
                    ForEach(FocusStudioViewMode.allCases) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                viewModeRaw = mode.rawValue
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(mode.rawValue)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                viewMode == mode ? Color.accent.opacity(0.18) : Color.white.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(viewMode == mode ? Color.accent.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1)
                            )
                            .foregroundColor(viewMode == mode ? .primaryText : .secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
            }

            // Metrics & Search Bar
            HStack(spacing: 12) {
                // Summary Metric Pills
                HStack(spacing: 8) {
                    metricPill(
                        icon: "flame.fill",
                        label: "\(snap.urgentItems.count) urgent",
                        color: snap.urgentItems.isEmpty ? .secondaryText : Color(hex: "FF5C5C")
                    )
                    metricPill(
                        icon: "person.2.fill",
                        label: "\(snap.clientGroups.count) clients · \(snap.clients.count) projects · \(snap.pendingDeliverablesCount) deliverables",
                        color: .accent
                    )
                    metricPill(
                        icon: "music.note",
                        label: "\(snap.personal.count) personal tracks",
                        color: .secondaryText
                    )
                }

                Spacer()

                // Search Bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.tertiaryText)
                    TextField("Filter projects, clients, or tasks…", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.primaryText)
                        .frame(width: 220)
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.tertiaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
            }
        }
    }

    private func metricPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondaryText)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.18), lineWidth: 0.5))
    }

    private func statusBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.accent)
                .font(.system(size: 12))
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primaryText)
            Spacer()
            Button {
                statusFeedbackMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundColor(.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accent.opacity(0.24), lineWidth: 1))
    }

    // MARK: - Urgency Alert Banner

    private func urgencyAlertBanner(items: [FocusActionableItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color(hex: "FF8A00"))
                    .font(.system(size: 12))
                Text("IMMEDIATE DEADLINES")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(Color(hex: "FF8A00"))
                Spacer()
                Text("\(items.count) require attention")
                    .font(.system(size: 11))
                    .foregroundColor(.secondaryText)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        urgentItemChip(item: item)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(hex: "FF8A00").opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "FF8A00").opacity(0.22), lineWidth: 1))
    }

    private func urgentItemChip(item: FocusActionableItem) -> some View {
        Button {
            expandedProjectIDs.insert(item.id)
            openProject(item.project)
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(item.urgency.badgeColor)
                    .frame(width: 6, height: 6)
                Text(item.project.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primaryText)
                    .lineLimit(1)
                Text(item.urgency.shortBadge)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(item.urgency.badgeColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(item.urgency.badgeBackground, in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.surfaceBg, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.subtleBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Main Work Area

    @ViewBuilder
    private func mainWorkArea(snapshot snap: FocusStudioSnapshot) -> some View {
        switch viewMode {
        case .split:
            HStack(alignment: .top, spacing: 22) {
                // Client Work Column (Left) - Split by Clients
                VStack(alignment: .leading, spacing: 14) {
                    columnHeader(
                        title: "Client Work",
                        subtitle: "\(snap.clientGroups.count) clients · \(snap.clients.count) projects",
                        icon: "person.2.fill",
                        color: .accent,
                        expandAction: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                viewModeRaw = FocusStudioViewMode.clientsExpanded.rawValue
                            }
                        }
                    )

                    // Client Base Folder & Create Client Toolbar
                    clientFolderControlBar

                    if snap.clientGroups.isEmpty {
                        emptyClientsCard
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(snap.clientGroups) { group in
                                FocusClientGroupSection(
                                    group: group,
                                    isGroupCollapsed: collapsedClientNames.contains(group.clientName),
                                    expandedProjectIDs: expandedProjectIDs,
                                    toggleGroupCollapse: { toggleClientGroupCollapse(group.clientName) },
                                    toggleProjectExpand: { toggleExpand($0) },
                                    openProject: openProject,
                                    onMoveProject: { proj in projectToMove = proj }
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                // Personal Work Column (Right)
                VStack(alignment: .leading, spacing: 14) {
                    columnHeader(
                        title: "Personal Music",
                        subtitle: "\(snap.personal.count) tracks in progress",
                        icon: "music.note.house.fill",
                        color: Color(hex: "8759E8"),
                        expandAction: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                viewModeRaw = FocusStudioViewMode.personalExpanded.rawValue
                            }
                        }
                    )

                    if snap.personal.isEmpty {
                        emptyPersonalCard
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(snap.personal) { item in
                                FocusPersonalCard(
                                    item: item,
                                    isExpanded: expandedProjectIDs.contains(item.id),
                                    toggleExpand: { toggleExpand(item.id) },
                                    open: { openProject(item.project) },
                                    onMoveToClient: { projectToMove = item.project }
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

        case .clientsExpanded:
            VStack(alignment: .leading, spacing: 16) {
                expandedHeader(
                    title: "Client Work",
                    countLabel: "\(snap.clientGroups.count) clients · \(snap.clients.count) projects",
                    icon: "person.2.fill",
                    color: .accent
                )

                // Client Base Folder & Create Client Toolbar
                clientFolderControlBar

                if snap.clientGroups.isEmpty {
                    emptyClientsCard
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(snap.clientGroups) { group in
                            FocusClientGroupSection(
                                group: group,
                                isGroupCollapsed: collapsedClientNames.contains(group.clientName),
                                expandedProjectIDs: expandedProjectIDs,
                                toggleGroupCollapse: { toggleClientGroupCollapse(group.clientName) },
                                toggleProjectExpand: { toggleExpand($0) },
                                openProject: openProject,
                                onMoveProject: { proj in projectToMove = proj }
                            )
                        }
                    }
                }
            }

        case .personalExpanded:
            VStack(alignment: .leading, spacing: 16) {
                expandedHeader(
                    title: "Personal Music",
                    countLabel: "\(snap.personal.count) personal tracks",
                    icon: "music.note.house.fill",
                    color: Color(hex: "8759E8")
                )

                if snap.personal.isEmpty {
                    emptyPersonalCard
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 16)], spacing: 16) {
                        ForEach(snap.personal) { item in
                            FocusPersonalCard(
                                item: item,
                                isExpanded: expandedProjectIDs.contains(item.id),
                                toggleExpand: { toggleExpand(item.id) },
                                open: { openProject(item.project) },
                                onMoveToClient: { projectToMove = item.project }
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Client Folder Control Bar

    private var clientFolderControlBar: some View {
        HStack(spacing: 8) {
            // Folder location pill with menu
            Menu {
                Button {
                    clientManager.revealInFinder(url: clientManager.clientWorkBaseURL)
                } label: {
                    Label("Reveal Base Folder in Finder", systemImage: "folder")
                }

                Button {
                    clientManager.chooseCustomBaseFolder()
                } label: {
                    Label("Change Base Folder…", systemImage: "folder.badge.gearshape")
                }

                Button {
                    renameFolderNameDraft = clientManager.clientWorkFolderName
                    showingRenameFolderAlert = true
                } label: {
                    Label("Rename Base Folder…", systemImage: "pencil")
                }

                if clientManager.customClientWorkFolderPath != nil {
                    Divider()
                    Button {
                        clientManager.resetToDefaultBaseFolder()
                    } label: {
                        Label("Reset to Default Location", systemImage: "arrow.counterclockwise")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.accent)
                    Text(clientManager.clientWorkFolderName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primaryText)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.tertiaryText)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.07), lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Client base folder: \(clientManager.clientWorkBaseURL.path)")

            Spacer()

            // + New Client Folder Button
            Button {
                newClientNameDraft = ""
                showingCreateClientAlert = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text("New Client Folder")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accent.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Create a folder for a new client on disk")
        }
        .padding(.horizontal, 2)
    }

    private func createClientFolderAction() {
        let trimmed = newClientNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let url = try clientManager.createClientFolder(named: trimmed)
            statusFeedbackMessage = "Created client folder at “\(url.lastPathComponent)”"
        } catch {
            statusFeedbackMessage = error.localizedDescription
        }
        newClientNameDraft = ""
    }

    private func renameBaseFolderAction() {
        let trimmed = renameFolderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try clientManager.renameClientWorkFolder(to: trimmed)
            statusFeedbackMessage = "Client work folder renamed to “\(trimmed)”"
        } catch {
            statusFeedbackMessage = error.localizedDescription
        }
        renameFolderNameDraft = ""
    }

    private func columnHeader(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        expandAction: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primaryText)
                Text("·")
                    .foregroundColor(.tertiaryText)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondaryText)
            }

            Spacer()

            Button(action: expandAction) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                    Text("Expand")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.secondaryText)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help("Expand \(title) to full width")
        }
        .padding(.horizontal, 4)
    }

    private func expandedHeader(
        title: String,
        countLabel: String,
        icon: String,
        color: Color
    ) -> some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primaryText)
                Text("(\(countLabel))")
                    .font(.system(size: 12))
                    .foregroundColor(.secondaryText)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    viewModeRaw = FocusStudioViewMode.split.rawValue
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 10, weight: .bold))
                    Text("Back to Split View")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 4)
    }

    private var emptyClientsCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 26))
                .foregroundColor(.secondaryText)
            Text("No Clients or Client Projects Yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primaryText)
            Text("Click “New Client Folder” above to create a folder on disk for a client, or use “Move to Client…” on any personal track.")
                .font(.system(size: 12))
                .foregroundColor(.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(Color.surfaceBg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.subtleBorder, lineWidth: 1))
    }

    private var emptyPersonalCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 26))
                .foregroundColor(.secondaryText)
            Text("No Personal Tracks Found")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primaryText)
            Text("Add or scan Ableton set folders to view and manage your creative tracks here.")
                .font(.system(size: 12))
                .foregroundColor(.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(Color.surfaceBg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.subtleBorder, lineWidth: 1))
    }

    private func toggleExpand(_ id: Project.ID) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if expandedProjectIDs.contains(id) {
                expandedProjectIDs.remove(id)
            } else {
                expandedProjectIDs.insert(id)
            }
        }
    }

    private func toggleClientGroupCollapse(_ clientName: String) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if collapsedClientNames.contains(clientName) {
                collapsedClientNames.remove(clientName)
            } else {
                collapsedClientNames.insert(clientName)
            }
        }
    }
}

// MARK: - Focus Client Group Section

private struct FocusClientGroupSection: View {
    let group: FocusClientGroup
    let isGroupCollapsed: Bool
    let expandedProjectIDs: Set<Project.ID>
    let toggleGroupCollapse: () -> Void
    let toggleProjectExpand: (Project.ID) -> Void
    let openProject: (Project) -> Void
    let onMoveProject: (Project) -> Void

    @ObservedObject private var clientManager = ClientWorkManager.shared

    private var isUnassignedGroup: Bool {
        group.clientName == FocusStudioOrganizer.unassignedClientName
    }

    private var clientFolderURL: URL {
        if isUnassignedGroup {
            return clientManager.clientWorkBaseURL
        }
        return clientManager.clientWorkBaseURL.appendingPathComponent(group.clientName, isDirectory: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Client Header Banner
            HStack(alignment: .center, spacing: 10) {
                Button(action: toggleGroupCollapse) {
                    HStack(spacing: 8) {
                        Image(systemName: isGroupCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondaryText)
                            .frame(width: 14)

                        Image(systemName: isUnassignedGroup ? "tray.and.arrow.down.fill" : "person.crop.square.fill")
                            .font(.system(size: 15))
                            .foregroundColor(isUnassignedGroup ? Color(hex: "FFAA2C") : .accent)

                        Text(group.clientName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.primaryText)
                    }
                }
                .buttonStyle(.plain)

                if isUnassignedGroup {
                    Text("Needs Assignment")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(hex: "FFAA2C"))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: "FFAA2C").opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }

                // Project count & task summary pill
                HStack(spacing: 4) {
                    Text("\(group.items.count) \(group.items.count == 1 ? "project" : "projects")")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondaryText)
                    if group.totalOpenTasks > 0 {
                        Text("· \(group.totalOpenTasks) open")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.accent)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))

                Spacer()

                // Urgent deadline badge if any
                if group.mostUrgentDeadline != .noDeadline {
                    Text(group.mostUrgentDeadline.shortBadge)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(group.mostUrgentDeadline.badgeColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(group.mostUrgentDeadline.badgeBackground, in: RoundedRectangle(cornerRadius: 4))
                }

                // Reveal Client Folder in Finder
                Button {
                    clientManager.revealInFinder(url: clientFolderURL)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundColor(.secondaryText)
                }
                .buttonStyle(.plain)
                .help(isUnassignedGroup ? "Reveal Client Work base folder in Finder" : "Reveal “\(group.clientName)” folder in Finder")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.03))

            // Client Projects List (when expanded)
            if !isGroupCollapsed {
                LazyVStack(spacing: 10) {
                    if group.items.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.system(size: 12))
                                .foregroundColor(.tertiaryText)
                            Text("No projects in this client folder yet. Move a project here using 'Move to Client…'")
                                .font(.system(size: 11))
                                .foregroundColor(.tertiaryText)
                            Spacer()
                        }
                        .padding(12)
                    } else {
                        ForEach(group.items) { item in
                            FocusClientCard(
                                item: item,
                                isExpanded: expandedProjectIDs.contains(item.id),
                                toggleExpand: { toggleProjectExpand(item.id) },
                                open: { openProject(item.project) },
                                onMoveToClient: { onMoveProject(item.project) }
                            )
                        }
                    }
                }
                .padding(10)
            }
        }
        .background(Color.surfaceBg.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.subtleBorder, lineWidth: 1))
    }
}

// MARK: - Focus Client Card

private struct FocusClientCard: View {
    let item: FocusActionableItem
    let isExpanded: Bool
    let toggleExpand: () -> Void
    let open: () -> Void
    let onMoveToClient: () -> Void

    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var metadataStore: ProjectMetadataStore

    @State private var newDeliverableTitle: String = ""
    @State private var newRevisionText: String = ""

    private var project: Project { item.project }
    private var metadata: ProjectMetadata { item.metadata }
    private var deliverables: [DeliverableItem] { item.effectiveDeliverables }
    private var revisions: [ProjectRevisionItem] { metadata.revisions ?? [] }
    private var isUnassignedClient: Bool {
        item.clientName == FocusStudioOrganizer.unassignedClientName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card Header
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(isUnassignedClient ? "NO CLIENT ASSIGNED" : item.clientName.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.6)
                                .foregroundColor(isUnassignedClient ? Color(hex: "FFAA2C") : .accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background((isUnassignedClient ? Color(hex: "FFAA2C") : Color.accent).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

                            if let service = metadata.serviceType {
                                Text(service.rawValue)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.secondaryText)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                            }
                        }

                        Text(project.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Deadline Badge
                    deadlineBadge

                    // Audio Play Button
                    if project.hasExports {
                        Button {
                            guard let track = project.sortedTracks.first else { return }
                            store.playTrack(track)
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 19))
                                .foregroundColor(.accent)
                        }
                        .buttonStyle(.plain)
                        .help("Play latest export")
                    }

                    // Expand Chevron
                    Button(action: toggleExpand) {
                        Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                            .font(.system(size: 16))
                            .foregroundColor(isExpanded ? .primaryText : .tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Collapse card" : "Expand deliverables & notes")
                }

                // Summary status strip
                HStack(spacing: 12) {
                    // Deliverables progress bar
                    HStack(spacing: 5) {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondaryText)
                        Text("\(item.completedDeliverablesCount)/\(item.totalDeliverablesCount) Deliverables")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondaryText)
                    }

                    if !item.unresolvedRevisions.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left.and.exclamationmark.bubble.right.fill")
                                .font(.system(size: 9))
                                .foregroundColor(Color(hex: "FF8A00"))
                            Text("\(item.unresolvedRevisions.count) notes")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color(hex: "FF8A00"))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color(hex: "FF8A00").opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }

                    Spacer()

                    if project.latestModification != .distantPast {
                        Text("Edited \(project.latestModification.compactAge)")
                            .font(.system(size: 10))
                            .foregroundColor(.tertiaryText)
                    }
                }
            }
            .padding(14)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggleExpand)

            // Expanded Details Section
            if isExpanded {
                Divider().background(Color.divider)

                VStack(alignment: .leading, spacing: 14) {
                    // 1. Deadline Management Row
                    deadlineSelectorRow

                    // 2. Deliverables Checklist
                    deliverablesMatrixSection

                    // 3. Client Revisions / Feedback Log
                    revisionsSection

                    // 4. Action Bar
                    cardActionBar
                }
                .padding(14)
                .background(Color.elevatedBg.opacity(0.4))
            }
        }
        .background(Color.surfaceBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.subtleBorder, lineWidth: 1))
    }

    private var deadlineBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.system(size: 9))
            Text(item.urgency.title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
        }
        .foregroundColor(item.urgency.badgeColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(item.urgency.badgeBackground, in: RoundedRectangle(cornerRadius: 5))
    }

    private var deadlineSelectorRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DELIVERY DEADLINE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(.tertiaryText)
                Spacer()
                if metadata.targetDeadline != nil {
                    Button("Clear") {
                        metadataStore.setTargetDeadline(nil, for: project)
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.secondaryText)
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                // Quick Presets
                Button("Today") {
                    metadataStore.setTargetDeadline(Date(), for: project)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("+3 Days") {
                    let date = Calendar.current.date(byAdding: .day, value: 3, to: Date())
                    metadataStore.setTargetDeadline(date, for: project)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("+1 Week") {
                    let date = Calendar.current.date(byAdding: .day, value: 7, to: Date())
                    metadataStore.setTargetDeadline(date, for: project)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Spacer()

                // DatePicker
                DatePicker(
                    "",
                    selection: Binding(
                        get: { metadata.targetDeadline ?? Date() },
                        set: { metadataStore.setTargetDeadline($0, for: project) }
                    ),
                    displayedComponents: [.date]
                )
                .labelsHidden()
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
    }

    private var deliverablesMatrixSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DELIVERABLES")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(.tertiaryText)
                Spacer()
                Text("\(item.completedDeliverablesCount) of \(item.totalDeliverablesCount) completed")
                    .font(.system(size: 10))
                    .foregroundColor(.secondaryText)
            }

            VStack(spacing: 4) {
                ForEach(deliverables) { del in
                    HStack(spacing: 8) {
                        Button {
                            metadataStore.toggleDeliverable(del.id, for: project)
                        } label: {
                            Image(systemName: del.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12))
                                .foregroundColor(del.isCompleted ? .accent : .secondaryText)
                        }
                        .buttonStyle(.plain)

                        Text(del.title)
                            .font(.system(size: 12))
                            .foregroundColor(del.isCompleted ? .tertiaryText : .primaryText)
                            .strikethrough(del.isCompleted, color: .tertiaryText)

                        Spacer()

                        Button {
                            metadataStore.deleteDeliverable(del.id, for: project)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                                .foregroundColor(.tertiaryText)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                    .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 4))
                }

                // Add Deliverable Field
                HStack(spacing: 6) {
                    TextField("Add deliverable (e.g. Club Master, Instrumental)…", text: $newDeliverableTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .onSubmit(addDeliverable)
                    if !newDeliverableTitle.isEmpty {
                        Button("Add", action: addDeliverable)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.accent)
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func addDeliverable() {
        let trimmed = newDeliverableTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        metadataStore.addDeliverable(title: trimmed, for: project)
        newDeliverableTitle = ""
    }

    private var revisionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("REVISION NOTES & FEEDBACK")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(.tertiaryText)
                Spacer()
                if !revisions.isEmpty {
                    Text("\(item.unresolvedRevisions.count) unresolved")
                        .font(.system(size: 10))
                        .foregroundColor(.secondaryText)
                }
            }

            if !revisions.isEmpty {
                VStack(spacing: 4) {
                    ForEach(revisions) { rev in
                        HStack(spacing: 8) {
                            Button {
                                metadataStore.toggleRevision(rev.id, for: project)
                            } label: {
                                Image(systemName: rev.isResolved ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 12))
                                    .foregroundColor(rev.isResolved ? .accent : Color(hex: "FF8A00"))
                            }
                            .buttonStyle(.plain)

                            if let stamp = rev.timestampLabel {
                                Text("[\(stamp)]")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.accent)
                            }

                            Text(rev.text)
                                .font(.system(size: 12))
                                .foregroundColor(rev.isResolved ? .tertiaryText : .primaryText)
                                .strikethrough(rev.isResolved, color: .tertiaryText)

                            Spacer()

                            Button {
                                metadataStore.deleteRevision(rev.id, for: project)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9))
                                    .foregroundColor(.tertiaryText)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            // Add Revision Field
            HStack(spacing: 6) {
                TextField("Add client note or fix item…", text: $newRevisionText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .onSubmit(addRevision)
                if !newRevisionText.isEmpty {
                    Button("Add", action: addRevision)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accent)
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func addRevision() {
        let trimmed = newRevisionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        metadataStore.addRevision(text: trimmed, for: project)
        newRevisionText = ""
    }

    private var cardActionBar: some View {
        HStack(spacing: 8) {
            Button {
                store.openInAbleton(project)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.right.square")
                    Text("Ableton Live")
                }
                .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button("Continue in HQ", action: open)
                .font(.system(size: 11))
                .buttonStyle(.bordered)
                .controlSize(.small)

            Spacer()

            Menu {
                Button {
                    onMoveToClient()
                } label: {
                    if isUnassignedClient {
                        Label("Assign to Client…", systemImage: "folder.badge.plus")
                    } else {
                        Label("Move to Another Client…", systemImage: "folder.badge.gearshape")
                    }
                }

                Divider()

                Button("Reclassify as Personal Track") {
                    metadataStore.setProjectKind(.personal, for: project)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11))
                    .foregroundColor(.tertiaryText)
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.top, 4)
    }
}

// MARK: - Focus Personal Card

private struct FocusPersonalCard: View {
    let item: FocusActionableItem
    let isExpanded: Bool
    let toggleExpand: () -> Void
    let open: () -> Void
    let onMoveToClient: () -> Void

    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var progressStore: ProjectProgressStore
    @EnvironmentObject private var todoStore: ProjectTodoStore
    @EnvironmentObject private var metadataStore: ProjectMetadataStore

    @State private var newTodoTitle: String = ""

    private var project: Project { item.project }
    private var progress: ProjectProgress { progressStore.progress(for: project) }
    private var todos: [ProjectTodo] { todoStore.todos(for: project) }
    private var metadata: ProjectMetadata { metadataStore.metadata(for: project) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card Header
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(progress.stage.title.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.6)
                                .foregroundColor(Color(hex: "8759E8"))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(hex: "8759E8").opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

                            if let bpm = project.bpmLabel {
                                Text("\(bpm) BPM")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.tertiaryText)
                            }
                        }

                        Text(project.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Optional Deadline Badge
                    if metadata.targetDeadline != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 9))
                            Text(item.urgency.title)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(item.urgency.badgeColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(item.urgency.badgeBackground, in: RoundedRectangle(cornerRadius: 5))
                    }

                    // Audio Play Button
                    if project.hasExports {
                        Button {
                            guard let track = project.sortedTracks.first else { return }
                            store.playTrack(track)
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 19))
                                .foregroundColor(.accent)
                        }
                        .buttonStyle(.plain)
                        .help("Play latest export")
                    }

                    // Expand Chevron
                    Button(action: toggleExpand) {
                        Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                            .font(.system(size: 16))
                            .foregroundColor(isExpanded ? .primaryText : .tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Collapse card" : "Expand to-dos & next move")
                }

                // Stage progress line
                HStack(spacing: 3) {
                    ForEach(ProjectStage.allCases, id: \.rawValue) { stage in
                        Capsule()
                            .fill(stage.workflowIndex <= progress.stage.workflowIndex ? Color(hex: "8759E8") : Color.divider)
                            .frame(height: 3)
                    }
                }

                // Next Move Snippet & Todo count
                HStack(spacing: 12) {
                    if !progress.nextMove.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "8759E8"))
                            Text(progress.nextMove)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primaryText)
                                .lineLimit(1)
                        }
                    } else {
                        Text("No next move defined")
                            .font(.system(size: 11))
                            .foregroundColor(.tertiaryText)
                    }

                    Spacer()

                    let openTodos = item.openTodos.count
                    if openTodos > 0 {
                        Text("\(openTodos) to-do\(openTodos == 1 ? "" : "s")")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondaryText)
                    }
                }
            }
            .padding(14)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggleExpand)

            // Expanded Details Section
            if isExpanded {
                Divider().background(Color.divider)

                VStack(alignment: .leading, spacing: 14) {
                    // 1. Stage Stepper Selector
                    stageSelectorRow

                    // 2. Next Move Editor
                    nextMoveEditor

                    // 3. To-dos Checklist
                    todosChecklistSection

                    // 4. Milestone / Target Deadline
                    personalDeadlineRow

                    // 5. Action Bar
                    personalActionBar
                }
                .padding(14)
                .background(Color.elevatedBg.opacity(0.4))
            }
        }
        .background(Color.surfaceBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.subtleBorder, lineWidth: 1))
    }

    private var stageSelectorRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PRODUCTION STAGE")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundColor(.tertiaryText)

            HStack(spacing: 4) {
                ForEach(ProjectStage.allCases, id: \.rawValue) { stage in
                    Button {
                        progressStore.setStage(stage, for: project)
                    } label: {
                        Text(stage.title)
                            .font(.system(size: 10, weight: stage == progress.stage ? .bold : .medium))
                            .foregroundColor(stage == progress.stage ? .white : .secondaryText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                stage == progress.stage ? Color(hex: "8759E8") : Color.white.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var nextMoveEditor: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("NEXT MOVE")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundColor(.tertiaryText)

            TextField("Add a concrete next move (e.g. write B-section bassline)…", text: progressStore.nextMoveBinding(for: project))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.primaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var todosChecklistSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TO-DOS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(.tertiaryText)
                Spacer()
                Text("\(todos.filter(\.isCompleted).count) of \(todos.count) completed")
                    .font(.system(size: 10))
                    .foregroundColor(.secondaryText)
            }

            if !todos.isEmpty {
                VStack(spacing: 4) {
                    ForEach(todos) { todo in
                        HStack(spacing: 8) {
                            Button {
                                todoStore.toggle(todo, for: project)
                            } label: {
                                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 12))
                                    .foregroundColor(todo.isCompleted ? Color(hex: "8759E8") : .secondaryText)
                            }
                            .buttonStyle(.plain)

                            Text(todo.title)
                                .font(.system(size: 12))
                                .foregroundColor(todo.isCompleted ? .tertiaryText : .primaryText)
                                .strikethrough(todo.isCompleted, color: .tertiaryText)

                            Spacer()

                            Button {
                                todoStore.remove(todo, from: project)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9))
                                    .foregroundColor(.tertiaryText)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            // Add Todo Field
            HStack(spacing: 6) {
                TextField("Add task or checklist item…", text: $newTodoTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .onSubmit(addTodo)
                if !newTodoTitle.isEmpty {
                    Button("Add", action: addTodo)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "8759E8"))
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func addTodo() {
        let trimmed = newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todoStore.add(trimmed, to: project)
        newTodoTitle = ""
    }

    private var personalDeadlineRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TARGET RELEASE / MILESTONE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(.tertiaryText)
                Spacer()
                if metadata.targetDeadline != nil {
                    Button("Clear") {
                        metadataStore.setTargetDeadline(nil, for: project)
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.secondaryText)
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                Button("+1 Week") {
                    let date = Calendar.current.date(byAdding: .day, value: 7, to: Date())
                    metadataStore.setTargetDeadline(date, for: project)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("+1 Month") {
                    let date = Calendar.current.date(byAdding: .month, value: 1, to: Date())
                    metadataStore.setTargetDeadline(date, for: project)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Spacer()

                DatePicker(
                    "",
                    selection: Binding(
                        get: { metadata.targetDeadline ?? Date() },
                        set: { metadataStore.setTargetDeadline($0, for: project) }
                    ),
                    displayedComponents: [.date]
                )
                .labelsHidden()
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
    }

    private var personalActionBar: some View {
        HStack(spacing: 8) {
            Button {
                store.openInAbleton(project)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.right.square")
                    Text("Ableton Live")
                }
                .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button("Continue in HQ", action: open)
                .font(.system(size: 11))
                .buttonStyle(.bordered)
                .controlSize(.small)

            Spacer()

            Menu {
                Button {
                    onMoveToClient()
                } label: {
                    Label("Move to Client…", systemImage: "folder.badge.gearshape")
                }

                Divider()

                Button("Reclassify as Client Project") {
                    metadataStore.setProjectKind(.client, for: project)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11))
                    .foregroundColor(.tertiaryText)
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.top, 4)
    }
}

// MARK: - Move Project to Client Sheet

private struct MoveProjectToClientSheet: View {
    let project: Project
    @ObservedObject var clientManager: ClientWorkManager
    let metadataStore: ProjectMetadataStore
    let todoStore: ProjectTodoStore
    let progressStore: ProjectProgressStore
    let onMoved: (String, String) -> Void
    let onCancel: () -> Void

    @State private var selectedClientName: String = ""
    @State private var isCreatingInlineClient = false
    @State private var inlineClientName = ""
    @State private var errorMessage: String? = nil
    @State private var isMoving = false

    private var availableClients: [String] {
        var names = Set(clientManager.discoveredClientNames.filter { $0 != FocusStudioOrganizer.unassignedClientName })
        if let currentClient = metadataStore.metadata(for: project).clientName,
           !currentClient.isEmpty,
           currentClient != FocusStudioOrganizer.unassignedClientName {
            names.insert(currentClient)
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var targetClient: String {
        isCreatingInlineClient ? inlineClientName.trimmingCharacters(in: .whitespacesAndNewlines) : selectedClientName
    }

    private var destinationPreviewURL: URL {
        let client = targetClient.isEmpty ? "Client Name" : targetClient
        return clientManager.clientWorkBaseURL
            .appendingPathComponent(client, isDirectory: true)
            .appendingPathComponent(project.folderURL.lastPathComponent, isDirectory: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.accent)
                    Text("Move Project to Client")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primaryText)
                }
                Text("Moves the Ableton project folder on disk into your client directory and preserves all project metadata, notes, and to-dos.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondaryText)
            }

            Divider().background(Color.divider)

            // Current location
            VStack(alignment: .leading, spacing: 4) {
                Text("PROJECT")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(.tertiaryText)
                Text(project.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primaryText)
                Text(project.folderURL.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // Client Selection
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("TARGET CLIENT")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(.tertiaryText)
                    Spacer()
                    Button(isCreatingInlineClient ? "Choose Existing" : "+ New Client") {
                        isCreatingInlineClient.toggle()
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.accent)
                    .buttonStyle(.plain)
                }

                if isCreatingInlineClient {
                    TextField("Enter new client name (e.g. Francisco Luz)", text: $inlineClientName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                } else {
                    if availableClients.isEmpty {
                        Text("No client folders found. Click “+ New Client” above to create one.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondaryText)
                    } else {
                        Picker("", selection: $selectedClientName) {
                            Text("Select a Client…").tag("")
                            ForEach(availableClients, id: \.self) { client in
                                Text(client).tag(client)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
            }

            // Destination Path Preview
            VStack(alignment: .leading, spacing: 4) {
                Text("NEW LOCATION ON DISK")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(.tertiaryText)
                Text(destinationPreviewURL.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.accent)
                    .lineLimit(2)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            Spacer()

            // Action Buttons
            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .disabled(isMoving)

                Spacer()

                Button {
                    performMove()
                } label: {
                    if isMoving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Move Project")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(targetClient.isEmpty || isMoving)
            }
        }
        .padding(24)
        .frame(width: 480, height: 420)
        .background(Color.surfaceBg)
        .onAppear {
            if let first = availableClients.first {
                selectedClientName = first
            }
        }
    }

    private func performMove() {
        let client = targetClient
        guard !client.isEmpty else { return }

        isMoving = true
        errorMessage = nil

        do {
            let newURL = try clientManager.moveProject(
                project,
                toClient: client,
                metadataStore: metadataStore,
                todoStore: todoStore,
                progressStore: progressStore
            )
            onMoved(client, newURL.path)
        } catch {
            isMoving = false
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Library Status & Scan View

private struct HomeLibraryStatusView: View {
    @EnvironmentObject private var store: AppStore
    let state: LibraryLoadPresentation

    var body: some View {
        VStack(spacing: 15) {
            statusIcon
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primaryText)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isActivelyScanning {
                scanActivity
            }
            actions
        }
        .padding(28)
        .frame(maxWidth: 560)
        .background(Color.surfaceBg, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.subtleBorder))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state {
        case .loading:
            Image(systemName: "waveform")
                .font(.system(size: 30, weight: .medium)).foregroundColor(.accent)
        case .chooseFolder:
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 34)).foregroundColor(.accent)
        case .unavailable:
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 34)).foregroundColor(.orange)
        case .noProjects:
            Image(systemName: "waveform.and.magnifyingglass")
                .font(.system(size: 34)).foregroundColor(.secondaryText)
        case .updating:
            Image(systemName: "waveform")
                .font(.system(size: 30, weight: .medium)).foregroundColor(.accent)
        case .ready:
            EmptyView()
        }
    }

    private var isActivelyScanning: Bool {
        if case .loading = state { return true }
        if case .updating = state { return true }
        return false
    }

    private var scanActivity: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let fraction = store.scanProgress?.fractionComplete {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .tint(.accent)
            .frame(maxWidth: 420)
            .accessibilityLabel("Library scan in progress")

            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 9))
                    .foregroundColor(.accent)
                Text(store.scanProgress.map { "Scanning \($0.currentFolder)" } ?? "Preparing library scan…")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 10)
                if let progress = store.scanProgress {
                    Text(progressSummary(progress))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.tertiaryText)
                        .fixedSize()
                }
            }
            .frame(maxWidth: 420)
        }
    }

    private func progressSummary(_ progress: ProjectScanProgress) -> String {
        let folders = progress.totalFolders.map {
            "\(progress.foldersScanned) of \($0) folders checked"
        } ?? "Counting folders"
        return "\(folders) · \(progress.projectsFound) projects found"
    }

    private var title: String {
        switch state {
        case .chooseFolder: return "Choose your music folder"
        case .unavailable: return "Music folder unavailable"
        case .loading: return "Loading your library…"
        case .updating: return "Updating your library…"
        case .noProjects: return "No Ableton projects found"
        case .ready: return "Library ready"
        }
    }

    private var message: String {
        switch state {
        case .chooseFolder:
            return "goodvibrations HQ is waiting for the folder that contains your Ableton projects."
        case .unavailable(let folderName):
            return "The saved folder “\(folderName)” can’t be reached. It may have moved or be on a disconnected drive."
        case .loading(let folderName):
            return "Scanning “\(folderName)” for Ableton sets and audio exports. This can take a moment after an update."
        case .updating(let folderName):
            return "Refreshing “\(folderName)”."
        case .noProjects(let folderName):
            return "Finished scanning “\(folderName)”, but no folders containing Ableton .als files were found."
        case .ready:
            return "Your projects are ready."
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch state {
        case .chooseFolder, .unavailable:
            Button("Choose Music Folder…", action: store.selectFolder)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .noProjects:
            HStack {
                Button("Choose Different Folder…", action: store.selectFolder)
                    .buttonStyle(.borderedProminent)
                Button("Scan Again") { Task { await store.scan() } }
                    .buttonStyle(.bordered)
            }
        case .loading, .updating:
            Text("You can leave this screen open; projects will appear automatically.")
                .font(.system(size: 10))
                .foregroundColor(.tertiaryText)
        case .ready:
            EmptyView()
        }
    }
}
