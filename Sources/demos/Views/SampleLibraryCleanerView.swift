import SwiftUI
import AppKit
import AVFoundation

struct SampleLibraryCleanerView: View {
    @ObservedObject var store: SampleLibraryCleanerStore = .shared
    @EnvironmentObject var appStore: AppStore
    @StateObject private var samplePlayer = SampleAudioPlayer.shared

    @State private var hoveredItemId: String?
    @State private var itemToCollect: SampleAuditItem?

    // Tinder Swipe Animation State
    @State private var dragOffset: CGSize = .zero
    @State private var swipeRotation: Double = 0.0

    var body: some View {
        VStack(spacing: 0) {
            topNavBar
            Divider().background(Color.divider)

            if store.isScanning {
                scanningBanner
                Divider().background(Color.divider)
            }

            if !store.auditItems.isEmpty {
                mainContentView
            } else if !store.isScanning {
                emptyStateView
            }
        }
        .background(Color.appBg)
        .frame(minWidth: 980, minHeight: 650)
        .alert(
            deleteAlertTitle,
            isPresented: $store.showDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                Task {
                    if store.deleteConfirmationSource == .selectedItems {
                        await store.moveItemsToTrash(ids: store.selectedItemIds)
                    } else {
                        await store.moveItemsToTrash(ids: store.markedForTrashIds)
                    }
                }
            }
        } message: {
            Text(deleteAlertMessage)
        }
        .sheet(item: $itemToCollect) { item in
            collectModal(for: item)
        }
        // Hidden keyboard shortcuts for Tinder Swiper
        .background {
            if store.viewMode == .tinderSwipe {
                Group {
                    Button("") {
                        swipeWithAnimation(isTrash: true)
                    }
                    .keyboardShortcut(.leftArrow, modifiers: [])

                    Button("") {
                        swipeWithAnimation(isTrash: false)
                    }
                    .keyboardShortcut(.rightArrow, modifiers: [])

                    Button("") {
                        if let card = store.currentSwipeCard {
                            samplePlayer.toggle(sampleId: card.id, url: card.fileURL)
                        }
                    }
                    .keyboardShortcut(.space, modifiers: [])

                    Button("") {
                        store.undoLastSwipe()
                    }
                    .keyboardShortcut("z", modifiers: .command)
                }
                .opacity(0)
                .allowsHitTesting(false)
            }
        }
    }

    private var deleteAlertTitle: String {
        if store.deleteConfirmationSource == .selectedItems {
            return "Move \(store.selectedCount) Samples to Trash?"
        } else {
            return "Move \(store.markedForTrashIds.count) Swiped Samples to Trash?"
        }
    }

    private var deleteAlertMessage: String {
        let size = store.deleteConfirmationSource == .selectedItems
            ? store.formattedSelectedBytes
            : store.formattedSwipedTrashBytes
        return "This will move \(size) of unused audio files to your macOS Trash. Your Ableton projects will not be modified, and you can restore files from the Trash at any time."
    }

    // MARK: - Top Nav Bar
    private var topNavBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 22))
                    .foregroundColor(.accent)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Sample Library Cleaner")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primaryText)
                    Text(store.libraryURL?.path ?? "No sample folder selected")
                        .font(.system(size: 10))
                        .foregroundColor(.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 260, alignment: .leading)
                }
            }

            Spacer()

            // Mode Picker: Folder Browser vs Tinder Swiper
            if !store.auditItems.isEmpty {
                Picker("", selection: $store.viewMode) {
                    ForEach(CleanerPresentationMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
                .onChange(of: store.viewMode) { _, newMode in
                    if newMode == .tinderSwipe {
                        store.prepareSwipeDeck()
                    }
                }
            }

            Spacer()

            // Change Library Folder Button
            Button(action: { store.chooseLibraryFolder() }) {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                    Text(store.libraryURL == nil ? "Choose Library…" : "Change…")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.surfaceBg)
                .cornerRadius(5)
            }
            .buttonStyle(.plain)

            // Scan / Cancel Scan Button
            if store.isScanning {
                Button(action: { store.cancelScan() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                        Text("Stop")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.85))
                    .foregroundColor(.white)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: {
                    store.startAudit(with: appStore.visibleProjects)
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("Scan Library")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(store.libraryURL == nil ? Color.gray.opacity(0.3) : Color.accent)
                    .foregroundColor(store.libraryURL == nil ? .secondaryText : .white)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .disabled(store.libraryURL == nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Scanning Banner
    private var scanningBanner: some View {
        VStack(spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(store.statusMessage)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.primaryText)
                }
                Spacer()
                Text("\(Int(store.scanProgress * 100))%")
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondaryText)
            }
            ProgressView(value: store.scanProgress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.accent.opacity(0.06))
    }

    // MARK: - Main Content View (Dual Pane with Pack Sidebar)
    private var mainContentView: some View {
        HSplitView {
            packSidebarView
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)

            VStack(spacing: 0) {
                if store.viewMode == .folderBrowser {
                    browserMetricsBar
                    Divider().background(Color.divider)
                    browserControlsBar
                    Divider().background(Color.divider)
                    sampleListView
                    Divider().background(Color.divider)
                    browserBottomBar
                } else {
                    tinderSwiperView
                }
            }
            .frame(minWidth: 640)
        }
    }

    // MARK: - Left Pack Sidebar
    private var packSidebarView: some View {
        VStack(spacing: 0) {
            // Header & Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.tertiaryText)
                    .font(.system(size: 10))
                TextField("Filter packs…", text: $store.folderSearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !store.folderSearchText.isEmpty {
                    Button(action: { store.folderSearchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.surfaceBg)
            .cornerRadius(5)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider().background(Color.divider)

            // Pack List
            ScrollView {
                LazyVStack(spacing: 1) {
                    // All Folders Item
                    packRow(
                        name: "All Sample Packs",
                        path: nil,
                        count: store.totalCount,
                        unusedBytes: store.unusedBytes,
                        isSelected: store.selectedPackPath == nil
                    )

                    ForEach(store.displayedPackFolders) { folder in
                        packRow(
                            name: folder.name,
                            path: folder.path,
                            count: folder.totalCount,
                            unusedBytes: folder.unusedBytes,
                            isSelected: store.selectedPackPath == folder.path
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(Color.appBg.opacity(0.95))
    }

    private func packRow(name: String, path: String?, count: Int, unusedBytes: Int64, isSelected: Bool) -> some View {
        Button(action: {
            store.selectedPackPath = path
            if store.viewMode == .tinderSwipe {
                store.prepareSwipeDeck()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: path == nil ? "square.grid.2x2.fill" : "folder.fill")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .accent : .secondaryText)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .white : .primaryText)
                        .lineLimit(1)
                    Text("\(count) samples")
                        .font(.system(size: 9.5))
                        .foregroundColor(.tertiaryText)
                }

                Spacer()

                if unusedBytes > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: unusedBytes, countStyle: .file))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12))
                        .cornerRadius(3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accent.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Browser Metrics Bar
    private var browserMetricsBar: some View {
        HStack(spacing: 10) {
            metricCard(title: "Total", value: "\(store.totalCount)", subtitle: store.formattedTotalBytes, icon: "waveform", color: .secondaryText)
            metricCard(title: "Unused", value: "\(store.unusedCount)", subtitle: "\(store.formattedUnusedBytes) reclaimable", icon: "checkmark.circle.fill", color: .green)
            metricCard(title: "Collected", value: "\(store.collectedCount)", subtitle: "\(store.formattedCollectedBytes) safe copies", icon: "doc.on.doc.fill", color: .orange)
            metricCard(title: "Active", value: "\(store.activeDependencyCount)", subtitle: "\(store.formattedActiveDependencyBytes) protected", icon: "lock.shield.fill", color: .blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.surfaceBg.opacity(0.3))
    }

    private func metricCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.secondaryText)
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primaryText)
                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundColor(color)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.surfaceBg)
        .cornerRadius(6)
    }

    // MARK: - Browser Controls Bar
    private var browserControlsBar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $store.filterMode) {
                ForEach(SampleCleanerFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.tertiaryText)
                    .font(.system(size: 10))
                TextField("Search in view…", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !store.searchText.isEmpty {
                    Button(action: { store.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondaryText)
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.surfaceBg)
            .cornerRadius(5)
            .frame(width: 200)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Sample List View
    private var sampleListView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(store.displayedItems) { item in
                    sampleRow(item)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func sampleRow(_ item: SampleAuditItem) -> some View {
        let isHovered = hoveredItemId == item.id
        let isSelected = store.selectedItemIds.contains(item.id)
        let isPlaying = samplePlayer.isPlaying && samplePlayer.currentSampleId == item.id

        return HStack(spacing: 10) {
            if item.status.isDeletable {
                Button(action: { store.toggleSelection(for: item.id) }) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13))
                        .foregroundColor(isSelected ? .accent : .tertiaryText)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.secondaryText.opacity(0.5))
                    .frame(width: 13)
            }

            Button(action: {
                samplePlayer.toggle(sampleId: item.id, url: item.fileURL)
            }) {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(isPlaying ? .orange : (isHovered ? .accent : .secondaryText))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.fileName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.primaryText)
                    .lineLimit(1)

                Text(item.relativePath)
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            statusBadge(for: item)

            Text(item.formattedSize)
                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                .foregroundColor(.secondaryText)
                .frame(width: 70, alignment: .trailing)

            Button(action: {
                NSWorkspace.shared.selectFile(item.fileURL.path, inFileViewerRootedAtPath: "")
            }) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 10))
                    .foregroundColor(isHovered ? .secondaryText : .clear)
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
            .frame(width: 16)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
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
        HStack(spacing: 5) {
            switch item.status {
            case .unused:
                HStack(spacing: 3) {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                    Text("Unused")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.12))
                .cornerRadius(4)

            case .collectedInProject(let names):
                HStack(spacing: 3) {
                    Circle().fill(Color.orange).frame(width: 5, height: 5)
                    Text("In: \(names.joined(separator: ", "))")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(4)

            case .activeDependency(let names):
                HStack(spacing: 5) {
                    HStack(spacing: 3) {
                        Circle().fill(Color.blue).frame(width: 5, height: 5)
                        Text("Active: \(names.joined(separator: ", "))")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.blue)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(4)

                    Button(action: { itemToCollect = item }) {
                        Text("Collect…")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accent)
                            .foregroundColor(.white)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Browser Bottom Bar
    private var browserBottomBar: some View {
        HStack(spacing: 12) {
            Button("Select All Unused") { store.selectAllUnused() }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.secondaryText)

            Button("Select All Duplicates") { store.selectAllCollected() }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.secondaryText)

            if !store.selectedItemIds.isEmpty {
                Button("Deselect All") { store.deselectAll() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondaryText)
            }

            Spacer()

            if store.selectedCount > 0 {
                Text("\(store.selectedCount) selected (\(store.formattedSelectedBytes))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondaryText)

                Button(action: {
                    store.deleteConfirmationSource = .selectedItems
                    store.showDeleteConfirmation = true
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                        Text("Move Selected to Trash")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.9))
                    .foregroundColor(.white)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.surfaceBg)
    }

    // MARK: - Tinder Swiper Mode ("Swipe Curation")
    private var tinderSwiperView: some View {
        VStack(spacing: 16) {
            // Deck Progress Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.selectedPackPath != nil ? store.selectedPackPath! : "All Safe Samples")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primaryText)

                    Text("Only showing samples with NO dependencies. Swiping left deletes, swiping right keeps.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondaryText)
                }

                Spacer()

                HStack(spacing: 8) {
                    Text("\(store.currentSwipeIndex) / \(store.swipeDeck.count)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondaryText)

                    if !store.markedForTrashIds.isEmpty {
                        Button(action: {
                            store.deleteConfirmationSource = .swipedTrashItems
                            store.showDeleteConfirmation = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash.fill")
                                Text("Trash \(store.markedForTrashIds.count) (\(store.formattedSwipedTrashBytes))")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.red.opacity(0.9))
                            .foregroundColor(.white)
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)

            // The Card Stack
            ZStack {
                if let nextCard = store.nextSwipeCard {
                    sampleCard(for: nextCard, isTopCard: false)
                        .scaleEffect(0.95)
                        .offset(y: 10)
                        .opacity(0.7)
                }

                if let card = store.currentSwipeCard {
                    sampleCard(for: card, isTopCard: true)
                        .offset(dragOffset)
                        .rotationEffect(.degrees(swipeRotation))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    dragOffset = value.translation
                                    swipeRotation = Double(value.translation.width / 18)
                                }
                                .onEnded { value in
                                    if value.translation.width < -100 {
                                        swipeWithAnimation(isTrash: true)
                                    } else if value.translation.width > 100 {
                                        swipeWithAnimation(isTrash: false)
                                    } else {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            dragOffset = .zero
                                            swipeRotation = 0
                                        }
                                    }
                                }
                        )
                } else {
                    completedDeckView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 380)

            // Swiper Action Controls
            if store.currentSwipeCard != nil {
                HStack(spacing: 24) {
                    // Left: TRASH
                    Button(action: { swipeWithAnimation(isTrash: true) }) {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(Color.red.opacity(0.15))
                                .frame(width: 54, height: 54)
                                .overlay {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.red)
                                }
                            Text("TRASH (←)")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.red)
                        }
                    }
                    .buttonStyle(.plain)

                    // Replay Audio Button
                    Button(action: {
                        if let card = store.currentSwipeCard {
                            samplePlayer.play(sampleId: card.id, url: card.fileURL)
                        }
                    }) {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(Color.surfaceBg)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.accent)
                                }
                            Text("REPLAY (Space)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)

                    // Undo Button
                    if !store.swipeHistory.isEmpty {
                        Button(action: { store.undoLastSwipe() }) {
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(Color.surfaceBg)
                                    .frame(width: 44, height: 44)
                                    .overlay {
                                        Image(systemName: "arrow.uturn.backward")
                                            .font(.system(size: 15))
                                            .foregroundColor(.secondaryText)
                                    }
                                Text("UNDO (⌘Z)")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondaryText)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // Right: KEEP
                    Button(action: { swipeWithAnimation(isTrash: false) }) {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(Color.green.opacity(0.15))
                                .frame(width: 54, height: 54)
                                .overlay {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.green)
                                }
                            Text("KEEP (→)")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.green)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBg)
    }

    private func swipeWithAnimation(isTrash: Bool) {
        let targetX: CGFloat = isTrash ? -500 : 500
        let targetRotation: Double = isTrash ? -25 : 25

        withAnimation(.easeOut(duration: 0.22)) {
            dragOffset = CGSize(width: targetX, height: 0)
            swipeRotation = targetRotation
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            dragOffset = .zero
            swipeRotation = 0
            if isTrash {
                store.swipeLeftTrash()
            } else {
                store.swipeRightKeep()
            }
        }
    }

    private func sampleCard(for item: SampleAuditItem, isTopCard: Bool) -> some View {
        let isPlaying = samplePlayer.isPlaying && samplePlayer.currentSampleId == item.id

        return ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.surfaceBg)
                .shadow(color: Color.black.opacity(0.25), radius: 10, y: 5)
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }

            VStack(spacing: 16) {
                // Top Tag Bar
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10))
                        Text(item.packFolder)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(4)

                    Spacer()

                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text(item.status == .unused ? "Unused Anywhere" : "Collected in Project")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(4)
                }

                Spacer()

                // Audio Waveform Graphic & Play Button
                VStack(spacing: 12) {
                    Button(action: {
                        samplePlayer.toggle(sampleId: item.id, url: item.fileURL)
                    }) {
                        Circle()
                            .fill(isPlaying ? Color.orange : Color.accent)
                            .frame(width: 58, height: 58)
                            .overlay {
                                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white)
                            }
                            .shadow(color: (isPlaying ? Color.orange : Color.accent).opacity(0.4), radius: 8, y: 3)
                    }
                    .buttonStyle(.plain)

                    // Simulated Waveform Bars
                    HStack(spacing: 3) {
                        ForEach(0..<28) { idx in
                            let height = max(4.0, (sin(Double(idx) * 0.45) * 16.0 + 18.0) * (isPlaying ? 1.0 : 0.6))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(isPlaying ? Color.orange.opacity(0.8) : Color.accent.opacity(0.45))
                                .frame(width: 3, height: CGFloat(height))
                        }
                    }
                    .frame(height: 38)
                }

                Spacer()

                // File Details
                VStack(spacing: 4) {
                    Text(item.fileName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primaryText)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)

                    Text(item.relativePath)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondaryText)
                        .lineLimit(1)

                    Text("\(item.formattedSize) • \(item.fileURL.pathExtension.uppercased())")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.accent)
                        .padding(.top, 2)
                }
            }
            .padding(22)

            // Tinder Stamp Overlays (When dragging)
            if isTopCard {
                if dragOffset.width < -30 {
                    stampOverlay(title: "TRASH", color: .red, alignment: .topTrailing)
                        .opacity(min(1.0, Double(-dragOffset.width) / 100))
                } else if dragOffset.width > 30 {
                    stampOverlay(title: "KEEP", color: .green, alignment: .topLeading)
                        .opacity(min(1.0, Double(dragOffset.width) / 100))
                }
            }
        }
        .frame(width: 440, height: 340)
    }

    private func stampOverlay(title: String, color: Color, alignment: Alignment) -> some View {
        VStack {
            HStack {
                if alignment == .topTrailing { Spacer() }
                Text(title)
                    .font(.system(size: 24, weight: .heavy, design: .monospaced))
                    .foregroundColor(color)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(color, lineWidth: 3)
                    }
                    .rotationEffect(.degrees(alignment == .topTrailing ? 15 : -15))
                    .padding(20)
                if alignment == .topLeading { Spacer() }
            }
            Spacer()
        }
    }

    private var completedDeckView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("Deck Reviewed!")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primaryText)

            Text("You've swiped through all available safe samples in this pack.\n\(store.markedForTrashIds.count) marked for Trash (\(store.formattedSwipedTrashBytes)).")
                .font(.system(size: 12))
                .foregroundColor(.secondaryText)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                if !store.markedForTrashIds.isEmpty {
                    Button(action: {
                        store.deleteConfirmationSource = .swipedTrashItems
                        store.showDeleteConfirmation = true
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "trash.fill")
                            Text("Move \(store.markedForTrashIds.count) to Trash")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                Button("Reset Deck") {
                    store.prepareSwipeDeck()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 6)
        }
        .frame(width: 440, height: 320)
        .background(Color.surfaceBg)
        .cornerRadius(14)
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

            Text("Select your sample library folder above and click 'Scan Library'.\ngoodvibrations HQ will quickly audit unused files in the background without slowing down your Mac.")
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
