import WidgetKit
import SwiftUI

// MARK: - Shared data model

struct FavouriteProject: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let path: String
}

struct FavouritesEntry: TimelineEntry, Sendable {
    let date: Date
    let projects: [FavouriteProject]
}

// MARK: - Timeline provider

struct Provider: TimelineProvider {
    static let favoritesFileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Backstage/favorites.json")
    }()

    func placeholder(in context: Context) -> FavouritesEntry {
        FavouritesEntry(date: .now, projects: [
            FavouriteProject(name: "My Project", path: ""),
            FavouriteProject(name: "Another Track", path: "")
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (FavouritesEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FavouritesEntry>) -> Void) {
        let entry = loadEntry()
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func loadEntry() -> FavouritesEntry {
        var projects: [FavouriteProject] = []
        if let data = try? Data(contentsOf: Self.favoritesFileURL),
           let paths = try? JSONDecoder().decode([String].self, from: data) {
            projects = paths.map { path in
                FavouriteProject(name: URL(fileURLWithPath: path).lastPathComponent, path: path)
            }
        }
        return FavouritesEntry(date: .now, projects: projects)
    }
}

// MARK: - Widget view

struct BackstageWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var maxProjects: Int { family == .systemSmall ? 3 : 6 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "music.note")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("goodvibrations HQ")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.bottom, 8)

            if entry.projects.isEmpty {
                Spacer()
                Text("Star projects in goodvibrations HQ\nto see them here")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entry.projects.prefix(maxProjects)) { project in
                        Button(intent: OpenProjectIntent(path: project.path)) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.accentColor.opacity(0.8))
                                Text(project.name)
                                    .font(.system(size: 12))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
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
        .description("Quick access to your favourite projects.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
