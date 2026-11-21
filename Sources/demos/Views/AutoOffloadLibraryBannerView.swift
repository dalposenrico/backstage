import SwiftUI

struct AutoOffloadLibraryBannerView: View {
    @ObservedObject var offloadStore = ProjectOffloadStore.shared
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: SettingsStore

    private var eligibleProjects: [Project] {
        offloadStore.eligibleProjectsForAutoOffload(
            in: store.visibleProjects,
            threshold: settings.autoOffloadThreshold
        )
    }

    private var isReadySection: Bool {
        store.selectedSidebarSection == .autoOffloadReady
    }

    private var shouldShow: Bool {
        if isReadySection { return true }
        if !offloadStore.activeOperations.isEmpty { return true }
        return settings.isAutoOffloadEnabled && !eligibleProjects.isEmpty
    }

    var body: some View {
        if shouldShow {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    if !offloadStore.activeOperations.isEmpty {
                        activeOperationsContent
                    } else if !eligibleProjects.isEmpty {
                        eligibleProjectsContent
                    } else {
                        emptyReadySectionContent
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.accent.opacity(0.06))

                Divider().background(Color.divider)
            }
        }
    }

    // MARK: - Subviews

    private var activeOperationsContent: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text("Offloading \(offloadStore.activeOperations.count) project\(offloadStore.activeOperations.count == 1 ? "" : "s") to Cloud…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primaryText)
                Text("Processing in background. Audio bounces remain offline on your Mac.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondaryText)
            }

            Spacer()
        }
    }

    private var eligibleProjectsContent: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: "icloud.and.arrow.up.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(eligibleProjects.count) project\(eligibleProjects.count == 1 ? "" : "s") ready to offload")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primaryText)

                    if let reclaimable = offloadStore.formattedReclaimableBytes(for: eligibleProjects) {
                        Text("• ~\(reclaimable) reclaimable")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.accent)
                    }
                }

                Text("Older than \(settings.autoOffloadThreshold.title) • Demo audio bounces stay local for instant auditioning")
                    .font(.system(size: 11))
                    .foregroundColor(.secondaryText)
            }

            Spacer()

            if !isReadySection {
                Button("View List") {
                    withAnimation {
                        store.selectedSidebarSection = .autoOffloadReady
                        store.selectedCollectionURL = nil
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondaryText)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.elevatedBg)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Button {
                offloadStore.performAutoOffload(
                    projects: store.projects,
                    threshold: settings.autoOffloadThreshold
                )
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.circle.fill")
                    Text("Offload All Ready (\(eligibleProjects.count))")
                }
                .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.accent)

            Menu {
                Section("Inactivity Threshold") {
                    ForEach(AutoOffloadAge.allCases, id: \.self) { age in
                        Button {
                            settings.autoOffloadThreshold = age
                            store.invalidateFilteredProjectsCache()
                        } label: {
                            if settings.autoOffloadThreshold == age {
                                Label(age.title, systemImage: "checkmark")
                            } else {
                                Text(age.title)
                            }
                        }
                    }
                }
                Divider()
                Toggle("Auto-Offload on Scan", isOn: $settings.isAutoOffloadEnabled)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12))
                    .foregroundColor(.secondaryText)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Adjust offload threshold and preferences")
        }
    }

    private var emptyReadySectionContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)

            Text("All caught up! No projects older than \(settings.autoOffloadThreshold.title) need offloading.")
                .font(.system(size: 12))
                .foregroundColor(.secondaryText)

            Spacer()

            if !settings.isAutoOffloadEnabled {
                Button("Enable Auto-Offload") {
                    settings.isAutoOffloadEnabled = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.accent)
            }

            Button("Show All Projects") {
                withAnimation {
                    store.selectedSidebarSection = .all
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondaryText)
        }
    }
}
