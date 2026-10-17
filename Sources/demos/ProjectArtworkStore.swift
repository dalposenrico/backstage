import Foundation
import AppKit
import SwiftUI

struct ProjectArtwork: Codable, Equatable {
    let filename: String
    let creator: String?
    let sourceURL: URL?
    let license: String?
}

enum ArtworkCropPosition: String, Codable, CaseIterable {
    case topLeading, top, topTrailing, leading, center, trailing, bottomLeading, bottom, bottomTrailing

    var alignment: Alignment {
        switch self {
        case .topLeading: return .topLeading
        case .top: return .top
        case .topTrailing: return .topTrailing
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        case .bottomLeading: return .bottomLeading
        case .bottom: return .bottom
        case .bottomTrailing: return .bottomTrailing
        }
    }

    var horizontalBias: CGFloat {
        switch self {
        case .topLeading, .leading, .bottomLeading: return 1
        case .topTrailing, .trailing, .bottomTrailing: return -1
        default: return 0
        }
    }

    var verticalBias: CGFloat {
        switch self {
        case .topLeading, .top, .topTrailing: return 1
        case .bottomLeading, .bottom, .bottomTrailing: return -1
        default: return 0
        }
    }
}

struct OpenverseImage: Identifiable, Decodable {
    let id: String
    let title: String?
    private let thumbnailString: String?
    private let imageURLString: String?
    let creator: String?
    private let landingURLString: String?
    let license: String?

    var thumbnail: URL? { thumbnailString.flatMap(URL.init(string:)) }
    var url: URL? { imageURLString.flatMap(URL.init(string:)) }
    var foreignLandingURL: URL? { landingURLString.flatMap(URL.init(string:)) }

    enum CodingKeys: String, CodingKey {
        case id, title, creator, license
        case thumbnailString = "thumbnail"
        case imageURLString = "url"
        case landingURLString = "foreign_landing_url"
    }
}

private struct OpenverseResponse: Decodable { let results: [OpenverseImage] }

@MainActor
final class ProjectArtworkStore: ObservableObject {
    @Published private(set) var artwork: [String: ProjectArtwork] = [:]
    @Published private(set) var coverIdeas: [String: [ProjectArtwork]] = [:]
    @Published private(set) var cropPositions: [String: ArtworkCropPosition] = [:]
    @Published var searchResults: [OpenverseImage] = []
    @Published var isSearching = false
    @Published var searchError: String?

    private let metadataURL: URL
    private let ideasURL: URL
    private let artworkDirectory: URL
    private let cropURL: URL
    private let imageCache = NSCache<NSURL, NSImage>()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Backstage", isDirectory: true)
        artworkDirectory = support.appendingPathComponent("Project Artwork", isDirectory: true)
        metadataURL = support.appendingPathComponent("project-artwork.json")
        ideasURL = support.appendingPathComponent("project-artwork-options.json")
        cropURL = support.appendingPathComponent("project-artwork-crops.json")
        try? FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: metadataURL),
           let saved = try? JSONDecoder().decode([String: ProjectArtwork].self, from: data) {
            artwork = saved
        }
        if let data = try? Data(contentsOf: ideasURL),
           let saved = try? JSONDecoder().decode([String: [ProjectArtwork]].self, from: data) {
            coverIdeas = saved
        }
        if let data = try? Data(contentsOf: cropURL),
           let saved = try? JSONDecoder().decode([String: ArtworkCropPosition].self, from: data) {
            cropPositions = saved
        }
    }

    func imageURL(for project: Project) -> URL? {
        guard let item = artwork[project.folderURL.path] else { return nil }
        let url = artworkDirectory.appendingPathComponent(item.filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func image(for project: Project) -> NSImage? {
        guard let item = artwork[project.folderURL.path] else { return nil }
        return image(for: item)
    }

    func metadata(for project: Project) -> ProjectArtwork? { artwork[project.folderURL.path] }

    func cropPosition(for project: Project) -> ArtworkCropPosition {
        cropPositions[project.folderURL.path] ?? .center
    }

    func setCropPosition(_ position: ArtworkCropPosition, for project: Project) {
        cropPositions[project.folderURL.path] = position
        persist()
    }

    func ideas(for project: Project) -> [ProjectArtwork] {
        coverIdeas[project.folderURL.path] ?? artwork[project.folderURL.path].map { [$0] } ?? []
    }

    func imageURL(for item: ProjectArtwork) -> URL? {
        let url = artworkDirectory.appendingPathComponent(item.filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func image(for item: ProjectArtwork) -> NSImage? {
        let url = artworkDirectory.appendingPathComponent(item.filename)
        if let cached = imageCache.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        imageCache.setObject(image, forKey: url as NSURL)
        return image
    }

    func activate(_ item: ProjectArtwork, for project: Project) {
        artwork[project.folderURL.path] = item
        persist()
    }

    func chooseLocalImage(for project: Project) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose artwork for \(project.name)"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in try? self?.saveImage(from: url, for: project, metadata: nil) }
        }
    }

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        var components = URLComponents(string: "https://api.openverse.org/v1/images/")!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "categories", value: "photograph"),
            URLQueryItem(name: "mature", value: "false"),
            URLQueryItem(name: "extension", value: "jpg"),
            URLQueryItem(name: "aspect_ratio", value: "square"),
            URLQueryItem(name: "page_size", value: "20")
        ]
        do {
            var request = URLRequest(url: components.url!, timeoutInterval: 20)
            request.setValue("goodvibrations-HQ/1.0 (macOS; artwork browser)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard http.statusCode == 200 else {
                if http.statusCode == 429 {
                    searchError = "Openverse is receiving too many searches right now. Wait a moment, then try again."
                    return
                }
                searchError = "Openverse returned an error (\(http.statusCode)). Try again in a moment."
                return
            }
            searchResults = try JSONDecoder().decode(OpenverseResponse.self, from: data).results
        } catch {
            if let decodingError = error as? DecodingError {
                searchError = "Openverse sent an unexpected result. Try another search. (\(decodingError.shortDescription))"
            } else {
                searchError = "Couldn’t reach Openverse. Check your connection and try again."
            }
        }
    }

    func select(_ image: OpenverseImage, for project: Project) async throws {
        guard let remoteURL = image.url ?? image.thumbnail else { throw URLError(.badURL) }
        let (temporaryURL, _) = try await URLSession.shared.download(from: remoteURL)
        try saveImage(
            from: temporaryURL,
            for: project,
            metadata: ProjectArtwork(filename: "", creator: image.creator, sourceURL: image.foreignLandingURL, license: image.license?.uppercased())
        )
    }

    func remove(for project: Project) {
        for item in ideas(for: project) {
            if let existing = imageURL(for: item) {
                imageCache.removeObject(forKey: existing as NSURL)
                try? FileManager.default.removeItem(at: existing)
            }
        }
        artwork.removeValue(forKey: project.folderURL.path)
        coverIdeas.removeValue(forKey: project.folderURL.path)
        cropPositions.removeValue(forKey: project.folderURL.path)
        persist()
    }

    private func saveImage(from source: URL, for project: Project, metadata: ProjectArtwork?) throws {
        let filename = UUID().uuidString + ".jpg"
        let destination = artworkDirectory.appendingPathComponent(filename)
        guard let image = NSImage(contentsOf: source),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.88]) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try jpeg.write(to: destination, options: .atomic)
        imageCache.setObject(image, forKey: destination as NSURL)
        let previous = artwork[project.folderURL.path]
        let item = ProjectArtwork(
            filename: filename,
            creator: metadata?.creator,
            sourceURL: metadata?.sourceURL,
            license: metadata?.license
        )
        artwork[project.folderURL.path] = item
        var ideas = coverIdeas[project.folderURL.path] ?? []
        if let previous, !ideas.contains(previous) { ideas.append(previous) }
        if !ideas.contains(item) { ideas.append(item) }
        coverIdeas[project.folderURL.path] = ideas
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(artwork) else { return }
        try? data.write(to: metadataURL, options: .atomic)
        if let ideasData = try? JSONEncoder().encode(coverIdeas) {
            try? ideasData.write(to: ideasURL, options: .atomic)
        }
        if let cropData = try? JSONEncoder().encode(cropPositions) {
            try? cropData.write(to: cropURL, options: .atomic)
        }
    }
}

private extension DecodingError {
    var shortDescription: String {
        switch self {
        case .dataCorrupted: return "invalid data"
        case .keyNotFound: return "missing field"
        case .typeMismatch: return "unexpected field"
        case .valueNotFound: return "empty field"
        @unknown default: return "decoding error"
        }
    }
}
