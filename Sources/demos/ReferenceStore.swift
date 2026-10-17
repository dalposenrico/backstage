import Foundation
import AppKit
import UniformTypeIdentifiers

enum StreamingService: String, Codable, CaseIterable {
    case spotify
    case appleMusic

    var title: String { self == .spotify ? "Spotify" : "Apple Music" }
    var icon: String { self == .spotify ? "music.note.list" : "apple.logo" }
}

struct StreamingReference: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    let url: URL
    let service: StreamingService

    init(id: UUID = UUID(), title: String, url: URL, service: StreamingService) {
        self.id = id
        self.title = title
        self.url = url
        self.service = service
    }

    var embedURL: URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        switch service {
        case .spotify:
            guard components.host?.lowercased() == "open.spotify.com" else { return nil }
            let parts = components.path.split(separator: "/")
            guard parts.count >= 2, ["playlist", "album", "track"].contains(String(parts[0])) else { return nil }
            components.path = "/embed/" + parts.prefix(2).joined(separator: "/")
        case .appleMusic:
            guard components.host?.lowercased().hasSuffix("music.apple.com") == true else { return nil }
            components.host = "embed.music.apple.com"
        }
        return components.url
    }

    static func make(title: String, urlText: String) -> StreamingReference? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https", let host = url.host?.lowercased() else { return nil }
        let service: StreamingService
        if host == "open.spotify.com" { service = .spotify }
        else if host == "music.apple.com" || host.hasSuffix(".music.apple.com") { service = .appleMusic }
        else { return nil }
        let fallback = service == .spotify ? "Spotify reference" : "Apple Music reference"
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return StreamingReference(title: cleanTitle.isEmpty ? fallback : cleanTitle, url: url, service: service)
    }

    var hasGenericTitle: Bool {
        title == "Spotify reference" || title == "Apple Music reference"
    }
}

struct ReferenceSongNote: Identifiable, Codable, Equatable {
    let id: UUID
    let url: URL
    let service: StreamingService
    var title: String
    var note: String

    init(id: UUID = UUID(), url: URL, service: StreamingService, title: String, note: String = "") {
        self.id = id
        self.url = url
        self.service = service
        self.title = title
        self.note = note
    }
}

enum StreamingMetadataResolver {
    static func title(for reference: StreamingReference) async -> String? {
        if reference.service == .spotify,
           var components = URLComponents(string: "https://open.spotify.com/oembed") {
            components.queryItems = [URLQueryItem(name: "url", value: reference.url.absoluteString)]
            if let url = components.url,
               let (data, _) = try? await URLSession.shared.data(from: url),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let title = object["title"] as? String,
               !title.isEmpty { return title }
        }

        var request = URLRequest(url: reference.url, timeoutInterval: 8)
        request.setValue("goodvibrations-HQ/1.0", forHTTPHeaderField: "User-Agent")
        if let (data, _) = try? await URLSession.shared.data(for: request),
           let html = String(data: data.prefix(1_000_000), encoding: .utf8),
           let title = metaTitle(in: html) { return title }
        return readablePathTitle(from: reference.url)
    }

    static func readablePathTitle(from url: URL) -> String? {
        let parts = url.path.split(separator: "/")
        guard let typeIndex = parts.firstIndex(where: { ["playlist", "album", "track"].contains(String($0)) }),
              parts.indices.contains(typeIndex + 1) else { return nil }
        let slug = String(parts[typeIndex + 1])
        guard slug.contains("-") else { return nil }
        return slug.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private static func metaTitle(in html: String) -> String? {
        let patterns = [
            #"<meta[^>]+property=[\"']og:title[\"'][^>]+content=[\"']([^\"']+)[\"']"#,
            #"<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+property=[\"']og:title[\"']"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { continue }
            return String(html[range])
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&quot;", with: "\"")
        }
        return nil
    }
}

@MainActor
final class ReferenceStore: ObservableObject {
    @Published private var pathsByProject: [String: [String]] = [:]
    @Published private var streamingByProject: [String: [StreamingReference]] = [:]
    @Published private var songsByReference: [UUID: [ReferenceSongNote]] = [:]
    private let storageKey = "projectReferencePaths"
    private let streamingStorageKey = "projectStreamingReferences"
    private let songNotesStorageKey = "streamingReferenceSongNotes"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([String: [String]].self, from: data) {
            pathsByProject = saved
        }
        if let data = UserDefaults.standard.data(forKey: streamingStorageKey),
           let saved = try? JSONDecoder().decode([String: [StreamingReference]].self, from: data) {
            streamingByProject = saved
        }
        if let data = UserDefaults.standard.data(forKey: songNotesStorageKey),
           let saved = try? JSONDecoder().decode([UUID: [ReferenceSongNote]].self, from: data) {
            songsByReference = saved
        }
    }

    func references(for project: Project) -> [URL] {
        (pathsByProject[project.folderURL.path] ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func addReferences(to project: Project) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio]
        panel.message = "Choose reference tracks for \(project.name)"
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                guard let self else { return }
                var paths = self.pathsByProject[project.folderURL.path] ?? []
                for url in panel.urls where !paths.contains(url.path) { paths.append(url.path) }
                self.pathsByProject[project.folderURL.path] = paths
                self.save()
            }
        }
    }

    func remove(_ url: URL, from project: Project) {
        pathsByProject[project.folderURL.path]?.removeAll { $0 == url.path }
        save()
    }

    func streamingReferences(for project: Project) -> [StreamingReference] {
        streamingByProject[project.folderURL.path] ?? []
    }

    func addStreamingReference(title: String, urlText: String, to project: Project) -> StreamingReference? {
        guard let reference = StreamingReference.make(title: title, urlText: urlText) else { return nil }
        var items = streamingByProject[project.folderURL.path] ?? []
        guard !items.contains(where: { $0.url == reference.url }) else { return nil }
        items.append(reference)
        streamingByProject[project.folderURL.path] = items
        save()
        return reference
    }

    func addStreamingReferenceResolvingTitle(title: String, urlText: String, to project: Project) async -> StreamingReference? {
        guard var reference = StreamingReference.make(title: title, urlText: urlText) else { return nil }
        if reference.hasGenericTitle, let resolved = await StreamingMetadataResolver.title(for: reference) {
            reference.title = resolved
        }
        var items = streamingByProject[project.folderURL.path] ?? []
        guard !items.contains(where: { $0.url == reference.url }) else { return nil }
        items.append(reference)
        streamingByProject[project.folderURL.path] = items
        save()
        return reference
    }

    func refreshGenericStreamingTitles(for project: Project) async {
        let key = project.folderURL.path
        let candidates = (streamingByProject[key] ?? []).filter(\.hasGenericTitle)
        guard !candidates.isEmpty else { return }
        for candidate in candidates {
            guard let title = await StreamingMetadataResolver.title(for: candidate),
                  let index = streamingByProject[key]?.firstIndex(where: { $0.id == candidate.id }) else { continue }
            streamingByProject[key]?[index].title = title
        }
        save()
    }

    func remove(_ reference: StreamingReference, from project: Project) {
        streamingByProject[project.folderURL.path]?.removeAll { $0.id == reference.id }
        songsByReference.removeValue(forKey: reference.id)
        save()
    }

    func songs(for reference: StreamingReference) -> [ReferenceSongNote] {
        songsByReference[reference.id] ?? []
    }

    func addSong(urlText: String, to reference: StreamingReference) async -> ReferenceSongNote? {
        guard let candidate = StreamingReference.make(title: "", urlText: urlText),
              candidate.url.path.split(separator: "/").contains("track") else { return nil }
        var songs = songsByReference[reference.id] ?? []
        guard !songs.contains(where: { $0.url == candidate.url }) else { return nil }
        let title = await StreamingMetadataResolver.title(for: candidate) ?? candidate.title
        let song = ReferenceSongNote(url: candidate.url, service: candidate.service, title: title)
        songs.append(song)
        songsByReference[reference.id] = songs
        save()
        return song
    }

    func updateNote(_ note: String, for song: ReferenceSongNote, in reference: StreamingReference) {
        guard let index = songsByReference[reference.id]?.firstIndex(where: { $0.id == song.id }) else { return }
        songsByReference[reference.id]?[index].note = note
        save()
    }

    func removeSong(_ song: ReferenceSongNote, from reference: StreamingReference) {
        songsByReference[reference.id]?.removeAll { $0.id == song.id }
        save()
    }

    func notedSongs(for project: Project) -> [(StreamingReference, ReferenceSongNote)] {
        streamingReferences(for: project).flatMap { reference in
            songs(for: reference)
                .filter { !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { (reference, $0) }
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pathsByProject) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
        if let streamingData = try? JSONEncoder().encode(streamingByProject) {
            UserDefaults.standard.set(streamingData, forKey: streamingStorageKey)
        }
        if let songData = try? JSONEncoder().encode(songsByReference) {
            UserDefaults.standard.set(songData, forKey: songNotesStorageKey)
        }
    }
}
