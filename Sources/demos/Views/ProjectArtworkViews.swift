import SwiftUI
import AppKit

struct ProjectArtworkImage: View {
    let project: Project
    @EnvironmentObject var artworkStore: ProjectArtworkStore

    var body: some View {
        Group {
            if let image = artworkStore.image(for: project) {
                PositionedCropImage(image: image, position: artworkStore.cropPosition(for: project))
            } else {
                LinearGradient(
                    colors: placeholderColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "waveform")
                        .font(.system(size: 34, weight: .light))
                        .foregroundColor(.white.opacity(0.38))
                }
            }
        }
        .clipped()
    }

    private var placeholderColors: [Color] {
        let palettes: [[Color]] = [
            [Color(hex: "4B346D"), Color(hex: "C88C73")],
            [Color(hex: "173A42"), Color(hex: "64949A")],
            [Color(hex: "532C3B"), Color(hex: "D1A45B")],
            [Color(hex: "29344D"), Color(hex: "786897")]
        ]
        return palettes[abs(project.name.hashValue) % palettes.count]
    }
}

private struct PositionedCropImage: View {
    let image: NSImage
    let position: ArtworkCropPosition

    var body: some View {
        GeometryReader { proxy in
            let sourceWidth = max(1, image.size.width)
            let sourceHeight = max(1, image.size.height)
            let scale = max(proxy.size.width / sourceWidth, proxy.size.height / sourceHeight)
            let renderedWidth = sourceWidth * scale
            let renderedHeight = sourceHeight * scale
            let overflowX = max(0, renderedWidth - proxy.size.width)
            let overflowY = max(0, renderedHeight - proxy.size.height)

            Image(nsImage: image)
                .resizable()
                .frame(width: renderedWidth, height: renderedHeight)
                .position(
                    x: proxy.size.width / 2 + position.horizontalBias * overflowX / 2,
                    y: proxy.size.height / 2 + position.verticalBias * overflowY / 2
                )
        }
        .clipped()
    }
}

struct ArtworkPickerView: View {
    let project: Project
    @EnvironmentObject var artworkStore: ProjectArtworkStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = "moody abstract"
    @State private var savingID: String?

    private let moods = ["moody abstract", "rainy night", "analog texture", "dreamy light", "film grain", "neon city"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose artwork").font(.system(size: 18, weight: .bold))
                    Text(project.name).font(.system(size: 11)).foregroundColor(.secondaryText)
                }
                Spacer()
                Button("Upload Photo…") { artworkStore.chooseLocalImage(for: project) }
                if artworkStore.imageURL(for: project) != nil {
                    Button("Remove") { artworkStore.remove(for: project); dismiss() }
                }
            }
            .padding(18)

            HStack(spacing: 8) {
                TextField("Search open photography…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await artworkStore.search(query) } }
                Button("Search") { Task { await artworkStore.search(query) } }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 18)

            if artworkStore.imageURL(for: project) != nil {
                HStack(spacing: 14) {
                    ProjectArtworkImage(project: project)
                        .frame(width: 116, height: 116)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("CROP POSITION")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.8)
                            .foregroundColor(.tertiaryText)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 3), spacing: 4) {
                            ForEach(ArtworkCropPosition.allCases, id: \.self) { position in
                                Button {
                                    artworkStore.setCropPosition(position, for: project)
                                } label: {
                                    Circle()
                                        .fill(artworkStore.cropPosition(for: project) == position ? Color.accent : Color.primary.opacity(0.08))
                                        .frame(width: 9, height: 9)
                                        .frame(width: 28, height: 28)
                                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 5))
                                }
                                .buttonStyle(.plain)
                                .help("Move crop to \(position.rawValue)")
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(moods, id: \.self) { mood in
                        Button(mood) { query = mood; Task { await artworkStore.search(mood) } }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
            .padding(12)

            if !artworkStore.ideas(for: project).isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("COVER IDEAS")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(.tertiaryText)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(artworkStore.ideas(for: project), id: \.filename) { item in
                                if let image = artworkStore.image(for: item) {
                                    Button { artworkStore.activate(item, for: project) } label: {
                                        Image(nsImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 72, height: 72)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(artworkStore.metadata(for: project) == item ? Color.accent : .clear, lineWidth: 3)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .help("Use this cover" + (item.creator.map { " · Photo by \($0)" } ?? ""))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            }

            if artworkStore.isSearching {
                Spacer(); ProgressView("Finding artwork…"); Spacer()
            } else if let error = artworkStore.searchError {
                Spacer(); Text(error).foregroundColor(.secondaryText); Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                        ForEach(artworkStore.searchResults) { item in
                            Button {
                                savingID = item.id
                                Task {
                                    try? await artworkStore.select(item, for: project)
                                    savingID = nil
                                }
                            } label: {
                                ZStack(alignment: .bottomLeading) {
                                    AsyncImage(url: item.thumbnail) { phase in
                                        if let image = phase.image {
                                            image
                                                .resizable()
                                                .scaledToFill()
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        }
                                        else { Color.hoverBg.overlay { ProgressView().controlSize(.small) } }
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .clipped()
                                    LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
                                    Text(item.creator.map { "Photo by \($0)" } ?? "Openverse photo")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .padding(8)
                                    if savingID == item.id { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                                }
                                .aspectRatio(1, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .help([item.title, item.license?.uppercased()].compactMap { $0 }.joined(separator: " · "))
                        }
                    }
                    .padding(16)
                }
            }

            HStack {
                Text("Openly licensed images via Openverse · creator and license are saved with your choice")
                    .font(.system(size: 10)).foregroundColor(.tertiaryText)
                Spacer()
            }
            .padding(12)
            .background(Color.sidebarBg)
        }
        .frame(width: 760, height: 620)
        .background(Color.appBg)
        .task { if artworkStore.searchResults.isEmpty { await artworkStore.search(query) } }
    }
}
