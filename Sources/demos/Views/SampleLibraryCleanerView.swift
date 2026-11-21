import SwiftUI
import AppKit
import AVFoundation

struct SampleLibraryCleanerView: View {
    @ObservedObject var store: SampleLibraryCleanerStore = .shared
    @EnvironmentObject var appStore: AppStore
    @StateObject private var samplePlayer = SampleAudioPlayer.shared

    @State private var hoveredItemId: String?
    @State private var targetProjectForCollect: Project?
    @State private var itemToCollect: SampleAuditItem?

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().background(Color.divider)

            if store.isScanning {
                scanningBanner
                Divider().background(Color.divider)
            }

            if !store.auditItems.isEmpty {
                metricsBar
                Divider().background(Color.divider)
                controlsBar
                Divider().background(Color.divider)
                sampleListView
                Divider().background(Color.divider)
                bottomActionBar
            } else if !store.isScanning {
                emptyStateView
            }
        }
        .background(Color.appBg)
        .frame(minWidth: 840, minHeight: 600)
        .alert(
            "Move \(store.selectedCount) Samples to Trash?",
            isPresented: $store.showDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                Task {
                    await store.moveSelectedToTrash()
                }
            }
        } message: {
            Text("This will move \(store.formattedSelectedBytes) of unused audio files to your macOS Trash. Your Ableton projects will not be modified, and you can restore files from the Trash at any time.")
        }
        .sheet(item: $itemToCollect) { item in
            collectModal(for: item)
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 16) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 26))
                .foregroundColor(.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text("Sample Library Cleaner")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primaryText)
                Text("Scan your sample packs to identify unused files and duplicates copied into project folders.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondaryText)
            }

            Spacer()

            // Library folder button
            Button(action: { store.chooseLibraryFolder() }) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                    Text(store.libraryURL?.lastPathComponent ?? "Choose Sample Library…")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.surfaceBg)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            // Scan Button
            Button(action: {
                store.startAudit(with: appStore.visibleProjects)
            }) {
                HStack(spacing: 6) {
                    if store.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                    }
                    Text(store.isScanning ? "Scanning…" : "Scan Library")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(store.libraryURL == nil ? Color.gray.opacity(0.3) : Color.accent)
                .foregroundColor(store.libraryURL == nil ? .secondaryText : .white)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(store.libraryURL == nil || store.isScanning)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Scanning Banner
    private var scanningBanner: some View {
        VStack(spacing: 8) {
            HStack {
                Text(store.statusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primaryText)
                Spacer()
                Text("\(Int(store.scanProgress * 100))%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondaryText)
            }
            ProgressView(value: store.scanProgress, total: 1.0)
                .progressViewStyle(.linear)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.accent.opacity(0.08))
    }

    // MARK: - Metrics Bar
    private var metricsBar: some View {
        HStack(spacing: 12) {
            metricCard(
                title: "Total Scanned",
                value: "\(store.totalCount)",
                subtitle: store.formattedTotalBytes,
                icon: "waveform",
                color: .secondaryText
            )

            metricCard(
                title: "Unused Anywhere",
                value: "\(store.unusedCount)",
                subtitle: "\(store.formattedUnusedBytes) reclaimable",
                icon: "checkmark.circle.fill",
                color: .green
            )

            metricCard(
                title: "Collected in Projects",
                value: "\(store.collectedCount)",
                subtitle: "\(store.formattedCollectedBytes) safe duplicates",
                icon: "doc.on.doc.fill",
                color: .orange
            )

            metricCard(
                title: "Active Dependencies",
                value: "\(store.activeDependencyCount)",
                subtitle: "\(store.formattedActiveDependencyBytes) protected",
                icon: "lock.shield.fill",
                color: .blue
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.surfaceBg.opacity(0.4))
    }

    private func metricCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondaryText)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primaryText)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundColor(color)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.surfaceBg)
        .cornerRadius(8)
    }

    // MARK: - Controls Bar (Search & Filter)
    private var controlsBar: some View {
        HStack(spacing: 16) {
            // Category Tabs
            Picker("", selection: $store.filterMode) {
                ForEach(SampleCleanerFilter.allCases) { filter in
                    Text(badgeLabel(for: filter)).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 480)

            Spacer()

            // Search Box
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.tertiaryText)
                    .font(.system(size: 11))
                TextField("Search by name, path, or project…", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                if !store.searchText.isEmpty {
                    Button(action: { store.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondaryText)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.surfaceBg)
            .cornerRadius(6)
            .frame(width: 240)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func badgeLabel(for filter: SampleCleanerFilter) -> String {
        switch filter {
        case .all: return "All (\(store.totalCount))"
        case .unused: return "Unused (\(store.unusedCount))"
        case .collected: return "Collected (\(store.collectedCount))"
        case .active: return "Active (\(store.activeDependencyCount))"
        }
    }

    // MARK: - Sample List View
    private var sampleListView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(store.displayedItems) { item in
                    sampleRow(item)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func sampleRow(_ item: SampleAuditItem) -> some View {
        let isHovered = hoveredItemId == item.id
        let isSelected = store.selectedItemIds.contains(item.id)
        let isPlaying = samplePlayer.isPlaying && samplePlayer.currentSampleId == item.id

        return HStack(spacing: 12) {
            // Selection Checkbox
            if item.status.isDeletable {
                Button(action: { store.toggleSelection(for: item.id) }) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundColor(isSelected ? .accent : .tertiaryText)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondaryText.opacity(0.5))
                    .frame(width: 14)
            }

            // Audition Play/Pause Button
            Button(action: {
                samplePlayer.toggle(sampleId: item.id, url: item.fileURL)
            }) {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(isPlaying ? .orange : (isHovered ? .accent : .secondaryText))
            }
            .buttonStyle(.plain)

            // File Name & Path
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primaryText)
                    .lineLimit(1)

                Text(item.relativePath)
                    .font(.system(size: 10))
                    .foregroundColor(.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            // Status Badge
            statusBadge(for: item)

            // File Size
            Text(item.formattedSize)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(.secondaryText)
                .frame(width: 75, alignment: .trailing)

            // Context Menu Button / Reveal in Finder
            Button(action: {
                NSWorkspace.shared.selectFile(item.fileURL.path, inFileViewerRootedAtPath: "")
            }) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11))
                    .foregroundColor(isHovered ? .secondaryText : .clear)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
            .frame(width: 20)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accent.opacity(0.12) : (isHovered ? Color.surfaceBg.opacity(0.6) : Color.clear))
        .onHover { h in
            if h { hoveredItemId = item.id } else if hoveredItemId == item.id { hoveredItemId = nil }
        }
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(item.fileURL.path, inFileViewerRootedAtPath: "")
            }
            if item.status.isDeletable {
                Button(isSelected ? "Deselect" : "Select") {
                    store.toggleSelection(for: item.id)
                }
            }
            if case .activeDependency(let projects) = item.status, let first = projects.first {
                Button("Collect into '\(first)'") {
                    itemToCollect = item
                }
            }
        }
    }

    private func statusBadge(for item: SampleAuditItem) -> some View {
        HStack(spacing: 6) {
            switch item.status {
            case .unused:
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("Unused")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.12))
                .cornerRadius(4)

            case .collectedInProject(let names):
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("In: \(names.joined(separator: ", "))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(4)
                .help("This sample was collected into \(names.joined(separator: ", ")). The copy in your library is a duplicate.")

            case .activeDependency(let names):
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.blue).frame(width: 6, height: 6)
                        Text("Active: \(names.joined(separator: ", "))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blue)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(4)

                    // Collect button
                    Button(action: { itemToCollect = item }) {
                        Text("Collect…")
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.accent)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Copy this sample into the project's Samples/Imported/ folder so the project is self-contained.")
                }
            }
        }
    }

    // MARK: - Bottom Action Bar
    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            Button("Select All Unused") {
                store.selectAllUnused()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondaryText)

            Button("Select All Duplicates") {
                store.selectAllCollected()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondaryText)

            if !store.selectedItemIds.isEmpty {
                Button("Deselect All") {
                    store.deselectAll()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondaryText)
            }

            Spacer()

            if store.selectedCount > 0 {
                Text("\(store.selectedCount) items selected (\(store.formattedSelectedBytes))")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.secondaryText)

                Button(action: {
                    store.showDeleteConfirmation = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text("Move Selected to Trash")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.9))
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.surfaceBg)
    }

    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondaryText.opacity(0.5))

            Text("No Samples Scanned Yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primaryText)

            Text("Select your sample library folder above and click 'Scan Library'.\ngoodvibrations HQ will cross-reference all samples against your Ableton Live projects.")
                .font(.system(size: 12))
                .foregroundColor(.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            if store.libraryURL == nil {
                Button("Choose Sample Library Folder…") {
                    store.chooseLibraryFolder()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
            } else {
                Button("Start Scan") {
                    store.startAudit(with: appStore.visibleProjects)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Collect Modal
    private func collectModal(for item: SampleAuditItem) -> some View {
        let matchingProjects = appStore.visibleProjects.filter { p in
            item.referencingProjects.contains(p.name)
        }

        return VStack(spacing: 16) {
            Text("Collect Sample into Project")
                .font(.system(size: 15, weight: .semibold))

            Text("Copy '\(item.fileName)' into a project's Samples/Imported/ folder. This makes the project self-contained so you can safely clean the sample library.")
                .font(.system(size: 11.5))
                .foregroundColor(.secondaryText)
                .multilineTextAlignment(.center)

            VStack(spacing: 6) {
                ForEach(matchingProjects) { project in
                    Button(action: {
                        Task {
                            await store.collectSampleIntoProject(item: item, targetProject: project)
                            itemToCollect = nil
                        }
                    }) {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                            Text("Collect into '\(project.name)'")
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.surfaceBg)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("Cancel") {
                itemToCollect = nil
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: 440)
    }
}
