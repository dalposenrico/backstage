import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline entry

struct BackstageWidgetEntry: TimelineEntry, Sendable {
    let date: Date
    let snapshot: WidgetSnapshotData?
}

// MARK: - Timeline provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> BackstageWidgetEntry {
        BackstageWidgetEntry(
            date: .now,
            snapshot: WidgetSnapshotData(
                updatedAt: .now,
                lastActiveProject: WidgetProjectSummary(
                    name: "Summer Jam 2026",
                    path: "/Users/producer/Music/Summer Jam 2026",
                    alsPath: "/Users/producer/Music/Summer Jam 2026/Summer Jam 2026.als",
                    lastModified: .now.addingTimeInterval(-1800),
                    bpm: 124,
                    musicalKey: "Fm",
                    trackName: "Summer Jam 2026 v3.wav",
                    isFavorite: true
                ),
                recentProjects: [
                    WidgetProjectSummary(name: "Midnight Drift", path: "/demo1", alsPath: "/demo1/set.als", lastModified: .now.addingTimeInterval(-3600), bpm: 120, musicalKey: "Am", trackName: "Mix 1", isFavorite: true),
                    WidgetProjectSummary(name: "Neon Sunrise", path: "/demo2", alsPath: "/demo2/set.als", lastModified: .now.addingTimeInterval(-7200), bpm: 128, musicalKey: "C", trackName: "Rough", isFavorite: false),
                    WidgetProjectSummary(name: "Bassline Groove", path: "/demo3", alsPath: "/demo3/set.als", lastModified: .now.addingTimeInterval(-14400), bpm: 122, musicalKey: "Gm", trackName: nil, isFavorite: false)
                ],
                favoriteProjects: [
                    WidgetProjectSummary(name: "Summer Jam 2026", path: "/demo0", alsPath: "/demo0/set.als", lastModified: .now, bpm: 124, musicalKey: "Fm", trackName: "v3", isFavorite: true),
                    WidgetProjectSummary(name: "Midnight Drift", path: "/demo1", alsPath: "/demo1/set.als", lastModified: .now.addingTimeInterval(-3600), bpm: 120, musicalKey: "Am", trackName: "Mix 1", isFavorite: true)
                ],
                totalProjectsCount: 18
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (BackstageWidgetEntry) -> Void) {
        if context.isPreview && WidgetDataStorage.load() == nil {
            completion(placeholder(in: context))
        } else {
            completion(BackstageWidgetEntry(date: .now, snapshot: WidgetDataStorage.load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BackstageWidgetEntry>) -> Void) {
        let entry = BackstageWidgetEntry(date: .now, snapshot: WidgetDataStorage.load())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Date Formatting Helper

private func formatRelativeTime(_ date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    if interval < 60 {
        return "Just now"
    } else if interval < 3600 {
        let mins = max(1, Int(interval / 60))
        return "\(mins)m ago"
    } else if interval < 86400 {
        let hours = max(1, Int(interval / 3600))
        return "\(hours)h ago"
    } else {
        let days = max(1, Int(interval / 86400))
        if days == 1 { return "Yesterday" }
        return "\(days)d ago"
    }
}

// MARK: - Widget View

struct BackstageWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemLarge:
            largeView
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    // MARK: - Large View (Flagship)

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerBar

            if let snapshot = entry.snapshot, snapshot.totalProjectsCount > 0 {
                if let active = snapshot.lastActiveProject {
                    heroCard(project: active)
                }

                HStack(alignment: .top, spacing: 12) {
                    // Recents Column
                    VStack(alignment: .leading, spacing: 6) {
                        sectionHeader(title: "RECENTS", systemImage: "clock.arrow.circlepath", count: snapshot.recentProjects.count)
                        let recentItems = Array(snapshot.recentProjects.prefix(4))
                        if recentItems.isEmpty {
                            emptyMiniSection(text: "No recent projects")
                        } else {
                            VStack(spacing: 4) {
                                ForEach(recentItems) { project in
                                    compactProjectRow(project: project)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    // Favorites Column
                    VStack(alignment: .leading, spacing: 6) {
                        sectionHeader(title: "FAVOURITES", systemImage: "star.fill", count: snapshot.favoriteProjects.count, iconColor: .yellow)
                        let favoriteItems = Array(snapshot.favoriteProjects.prefix(4))
                        if favoriteItems.isEmpty {
                            emptyMiniSection(text: "Star projects in HQ to see them here")
                        } else {
                            VStack(spacing: 4) {
                                ForEach(favoriteItems) { project in
                                    compactProjectRow(project: project)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                emptyStateView
            }
        }
        .padding(14)
    }

    // MARK: - Medium View

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerBar

            if let snapshot = entry.snapshot, snapshot.totalProjectsCount > 0 {
                HStack(alignment: .top, spacing: 12) {
                    if let active = snapshot.lastActiveProject {
                        heroCard(project: active, isCompact: true)
                            .frame(maxWidth: .infinity)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        sectionHeader(title: "RECENTS", systemImage: "clock", count: snapshot.recentProjects.count)
                        let recentItems = Array(snapshot.recentProjects.prefix(3))
                        VStack(spacing: 3) {
                            ForEach(recentItems) { project in
                                compactProjectRow(project: project)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                emptyStateView
            }
        }
        .padding(12)
    }

    // MARK: - Small View

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tint)
                Text("goodvibrations")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if let active = entry.snapshot?.lastActiveProject {
                Text("LAST ACTIVE")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)

                Text(active.name)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(2)

                Text(formatRelativeTime(active.lastModified))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Button(intent: OpenProjectInAbletonIntent(alsPath: active.alsPath, folderPath: active.path)) {
                        Label("Live", systemImage: "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button(intent: OpenProjectInFinderIntent(path: active.path)) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                Spacer()
                Text("Open goodvibrations HQ to start.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(10)
    }

    // MARK: - Subviews

    private var headerBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tint)
            Text("goodvibrations HQ")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.primary)

            if let count = entry.snapshot?.totalProjectsCount, count > 0 {
                Text("· \(count) projects")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(intent: OpenProjectInHQIntent(path: "")) {
                HStack(spacing: 3) {
                    Text("Open HQ")
                        .font(.system(size: 9, weight: .medium))
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 8))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func heroCard(project: WidgetProjectSummary, isCompact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 5 : 8) {
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                Text("LAST ACTIVE PROJECT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatRelativeTime(project.lastModified))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: isCompact ? 13 : 15, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    if let bpm = project.bpm, bpm > 0 {
                        Text("\(Int(round(bpm))) BPM")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                    }
                    if let key = project.musicalKey, !key.isEmpty {
                        Text(key)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                    }
                    if let track = project.trackName, !track.isEmpty {
                        Text(track)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            HStack(spacing: 6) {
                Button(intent: OpenProjectInAbletonIntent(alsPath: project.alsPath, folderPath: project.path)) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                        Text("Open Live")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(intent: OpenProjectInFinderIntent(path: project.path)) {
                    HStack(spacing: 3) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 9))
                        Text("Finder")
                            .font(.system(size: 10))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(intent: OpenProjectInHQIntent(path: project.path)) {
                    HStack(spacing: 3) {
                        Image(systemName: "macwindow")
                            .font(.system(size: 9))
                        Text("HQ")
                            .font(.system(size: 10))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(isCompact ? 8 : 10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func sectionHeader(title: String, systemImage: String, count: Int, iconColor: Color = .secondary) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 8))
                .foregroundStyle(iconColor)
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func compactProjectRow(project: WidgetProjectSummary) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(formatRelativeTime(project.lastModified))
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            // 1-Click Launch Ableton
            Button(intent: OpenProjectInAbletonIntent(alsPath: project.alsPath, folderPath: project.path)) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .help("Open in Ableton Live")

            // 1-Click Reveal in Finder
            Button(intent: OpenProjectInFinderIntent(path: project.path)) {
                Image(systemName: "folder")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open in Finder")

            // 1-Click Open in goodvibrations HQ
            Button(intent: OpenProjectInHQIntent(path: project.path)) {
                Image(systemName: "macwindow")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open in goodvibrations HQ")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 5))
    }

    private func emptyMiniSection(text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "music.note.house")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("No Projects Found")
                .font(.system(size: 13, weight: .semibold))
            Text("Open goodvibrations HQ and choose your music folder to populate your projects.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(intent: OpenProjectInHQIntent(path: "")) {
                Text("Launch goodvibrations HQ")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Widget definition

struct BackstageWidget: Widget {
    let kind = "BackstageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            BackstageWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("goodvibrations HQ")
        .description("Quick access to your recent and favourite projects with 1-click launch into Ableton Live, Finder, and HQ.")
        .supportedFamilies([.systemLarge, .systemMedium, .systemSmall])
    }
}
