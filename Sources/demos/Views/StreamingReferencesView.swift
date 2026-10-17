import SwiftUI
import AppKit

struct StreamingReferencesSection: View {
    let project: Project
    @EnvironmentObject private var references: ReferenceStore
    @State private var showingAdd = false
    @State private var expandedReferenceID: UUID?
    @State private var addingSongTo: StreamingReference?
    @State private var showingNotesOverview = false

    var body: some View {
        let items = references.streamingReferences(for: project)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Vibe References", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primaryText)
                Spacer()
                if !references.notedSongs(for: project).isEmpty {
                    Button {
                        showingNotesOverview.toggle()
                        AccountDiagnostics.record("Reference notes overview \(showingNotesOverview ? "expanded" : "collapsed") inline")
                    } label: {
                        Image(systemName: showingNotesOverview ? "note.text.badge.plus" : "note.text")
                    }
                        .buttonStyle(.plain)
                        .help("Show all reference notes")
                }
                Button { showingAdd = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                    .help("Add Spotify or Apple Music reference")
            }

            if items.isEmpty {
                Button { showingAdd = true } label: {
                    Label("Add a Spotify or Apple Music link", systemImage: "link.badge.plus")
                        .font(.system(size: 11))
                        .foregroundColor(.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.hoverBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            } else {
                ForEach(items) { item in
                    VStack(spacing: 0) {
                        HStack(spacing: 9) {
                            Button { toggle(item) } label: {
                                Image(systemName: expandedReferenceID == item.id ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .frame(width: 12)
                            }.buttonStyle(.plain)
                            Image(systemName: item.service.icon).foregroundColor(.accent).frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Text("\(item.service.title) · \(references.songs(for: item).count) songs")
                                    .font(.system(size: 10)).foregroundColor(.tertiaryText)
                            }
                            Spacer()
                            Button {
                                AccountDiagnostics.record("Handed \(item.service.rawValue) reference to provider")
                                NSWorkspace.shared.open(item.url)
                            } label: {
                                Image(systemName: "arrow.up.forward.app")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(width: 26, height: 24)
                            }
                            .buttonStyle(.plain)
                            .help("Open playlist in \(item.service.title)")
                        }
                        .padding(9)

                        if expandedReferenceID == item.id {
                            Divider()
                            VStack(spacing: 8) {
                                ForEach(references.songs(for: item)) { song in
                                    ReferenceSongRow(song: song, reference: item)
                                }
                                Button { addingSongTo = item } label: {
                                    Label("Add song link", systemImage: "plus.circle")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 3)
                            }
                            .padding(9)
                        }
                    }
                    .background(Color.hoverBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contextMenu { Button("Remove", role: .destructive) { references.remove(item, from: project) } }
                }
            }

            if showingNotesOverview {
                InlineReferenceNotesOverview(project: project)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.white.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .sheet(isPresented: $showingAdd) { AddStreamingReferenceView(project: project) }
        .sheet(item: $addingSongTo) { reference in AddReferenceSongView(reference: reference) }
        .task(id: project.id) { await references.refreshGenericStreamingTitles(for: project) }
    }

    private func toggle(_ reference: StreamingReference) {
        expandedReferenceID = expandedReferenceID == reference.id ? nil : reference.id
    }
}

private struct ReferenceSongRow: View {
    let song: ReferenceSongNote
    let reference: StreamingReference
    @EnvironmentObject private var references: ReferenceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(song.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Spacer()
                Button { NSWorkspace.shared.open(song.url) } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.plain).help("Open song in \(song.service.title)")
            }
            TextField("What do you like about this song?", text: Binding(
                get: { references.songs(for: reference).first(where: { $0.id == song.id })?.note ?? "" },
                set: { references.updateNote($0, for: song, in: reference) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11))
        }
        .padding(8)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
        .contextMenu { Button("Remove Song", role: .destructive) { references.removeSong(song, from: reference) } }
    }
}

private struct AddReferenceSongView: View {
    let reference: StreamingReference
    @EnvironmentObject private var references: ReferenceStore
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var isAdding = false
    @State private var invalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a song").font(.headline)
            Text("Paste an Apple Music or Spotify song link. HQ will fetch its title automatically.")
                .font(.caption).foregroundColor(.secondaryText)
            TextField("Song link", text: $url)
            if invalid { Text("Use a supported song link that isn’t already in this playlist.").font(.caption).foregroundColor(.red) }
            HStack {
                if isAdding { ProgressView().controlSize(.small); Text("Getting song name…").font(.caption) }
                Spacer(); Button("Cancel") { dismiss() }
                Button("Add") { Task { await add() } }.disabled(url.isEmpty || isAdding).keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 450)
    }

    private func add() async {
        isAdding = true
        if await references.addSong(urlText: url, to: reference) != nil { dismiss() }
        else { invalid = true; isAdding = false }
    }
}

private struct InlineReferenceNotesOverview: View {
    let project: Project
    @EnvironmentObject private var references: ReferenceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("All Song Notes", systemImage: "text.quote")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondaryText)
            ForEach(references.notedSongs(for: project), id: \.1.id) { reference, song in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(song.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        Spacer()
                        Button { NSWorkspace.shared.open(song.url) } label: {
                            Image(systemName: "arrow.up.forward.app").font(.system(size: 10))
                        }.buttonStyle(.plain)
                    }
                    Text(reference.title).font(.system(size: 9)).foregroundColor(.tertiaryText).lineLimit(1)
                    Text(song.note).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(10)
        .background(Color.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AddStreamingReferenceView: View {
    let project: Project
    @EnvironmentObject private var references: ReferenceStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var url = ""
    @State private var invalid = false
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a vibe reference").font(.system(size: 18, weight: .bold))
            Text("Paste a Spotify or Apple Music playlist, album, or song link.")
                .font(.system(size: 12)).foregroundColor(.secondaryText)
            TextField("Name override (optional)", text: $title)
            TextField("https://open.spotify.com/… or https://music.apple.com/…", text: $url)
            if invalid { Text("That doesn’t look like a supported Spotify or Apple Music link.").font(.system(size: 11)).foregroundColor(.red) }
            HStack {
                if isAdding { ProgressView().controlSize(.small); Text("Getting playlist name…").font(.caption).foregroundColor(.secondaryText) }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { Task { await add() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(url.isEmpty || isAdding)
            }
        }
        .padding(22).frame(width: 460)
    }

    private func add() async {
        isAdding = true
        if await references.addStreamingReferenceResolvingTitle(title: title, urlText: url, to: project) != nil {
            dismiss()
        }
        else { invalid = true; isAdding = false }
    }
}
