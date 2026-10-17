import SwiftUI
import AppKit

struct ProjectNameGeneratorView: View {
    private struct TagGroup: Identifiable {
        let title: String
        let tags: [String]
        var id: String { title }
    }

    private static let tagGroups = [
        TagGroup(title: "GENRE + RHYTHM", tags: ["UKG", "4x4", "House", "Garage", "Breaks", "Jungle", "Ambient", "Pop"]),
        TagGroup(title: "EMOTION", tags: ["Sad", "Happy", "Euphoric", "Melancholic", "Angry", "Romantic", "Lonely", "Hopeful", "Anxious", "Bittersweet", "Nostalgic", "Mysterious"]),
        TagGroup(title: "TEXTURE", tags: ["Gritty", "Dreamy", "Raw", "Glossy", "Warm", "Cold", "Dark", "Airy", "Minimal", "Heavy"]),
        TagGroup(title: "WORLD", tags: ["Night Drive", "Rainy City", "Summer", "Afterhours", "Ocean", "Space", "Underground", "Sunrise", "90s", "Futuristic"])
    ]

    @State private var selectedTags = Set<String>()
    @State private var customTag = ""
    @State private var history = ProjectNameWorldHistory()
    @State private var variation = 0
    @State private var copiedName: String?
    @FocusState private var customTagFocused: Bool

    private var currentWorld: ProjectNameWorld? { history.current }
    private var suggestions: [String] { currentWorld?.suggestions ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    tagPicker
                    worldNavigation

                    if suggestions.isEmpty {
                        emptyState
                    } else {
                        results
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 680, minHeight: 620)
        .background(Color.appBg)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe.europe.africa.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.accent)
                .frame(width: 38, height: 38)
                .background(Color.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text("Name Worlds")
                    .font(.system(size: 20, weight: .bold))
                Text("Mix tags, then travel through different worlds of names.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondaryText)
            }
            Spacer()
            Label("LOCAL ONLY", systemImage: "lock.fill")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(.tertiaryText)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var tagPicker: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("BUILD A VIBE")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.7)
                        .foregroundColor(.tertiaryText)
                    Text("Pick as many tags as you want.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondaryText)
                }
                Spacer()
                if !selectedTags.isEmpty {
                    Button("Clear tags") { selectedTags.removeAll() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10))
                        .foregroundColor(.secondaryText)
                }
            }

            ForEach(Self.tagGroups) { group in
                VStack(alignment: .leading, spacing: 7) {
                    Text(group.title)
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.6)
                        .foregroundColor(.tertiaryText)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(group.tags, id: \.self) { tag in
                                tagButton(tag)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.tertiaryText)
                TextField("Add your own tag", text: $customTag)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($customTagFocused)
                    .onSubmit(addCustomTags)
                Button("Add", action: addCustomTags)
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.accent)
                    .disabled(customTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            if !customSelectedTags.isEmpty {
                HStack(spacing: 7) {
                    ForEach(customSelectedTags, id: \.self) { tag in tagButton(tag) }
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.divider))
    }

    private var customSelectedTags: [String] {
        selectedTags.filter { tag in
            !Self.tagGroups.contains { $0.tags.contains(tag) }
        }.sorted()
    }

    private func tagButton(_ tag: String) -> some View {
        let isSelected = selectedTags.contains(tag)
        return Button {
            if isSelected { selectedTags.remove(tag) }
            else { selectedTags.insert(tag) }
        } label: {
            HStack(spacing: 5) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                }
                Text(tag)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(isSelected ? .black : .secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accent : Color.white.opacity(0.045), in: Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.clear : Color.divider))
        }
        .buttonStyle(.plain)
    }

    private var worldNavigation: some View {
        HStack(spacing: 14) {
            Button(action: previousWorld) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.045), in: Circle())
                    .overlay(Circle().stroke(Color.divider))
            }
            .buttonStyle(.plain)
            .disabled(!history.canGoBack)
            .opacity(history.canGoBack ? 1 : 0.3)
            .help("Previous world")

            VStack(spacing: 3) {
                Text(currentWorld == nil ? "YOUR FIRST WORLD" : "WORLD \(history.position)")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                Text(worldDescription)
                    .font(.system(size: 10))
                    .foregroundColor(.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            Button(action: nextWorld) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: 44, height: 44)
                    .background(Color.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Generate a new world")
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .padding(.horizontal, 10)
    }

    private var worldDescription: String {
        guard let world = currentWorld else {
            return selectedTags.isEmpty ? "No idea? Just press →" : selectedTags.sorted().joined(separator: " · ")
        }
        return world.tags.joined(separator: " · ")
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "arrow.right.circle")
                .font(.system(size: 25))
                .foregroundColor(.accent.opacity(0.8))
            Text("Press the right arrow to enter a world")
                .font(.system(size: 13, weight: .semibold))
            Text("Choose tags first, or leave it empty and let the generator surprise you.")
                .font(.system(size: 11))
                .foregroundColor(.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("NAMES FROM THIS WORLD")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.7)
                    .foregroundColor(.tertiaryText)
                Spacer()
                Text("Click a name to copy it")
                    .font(.system(size: 10))
                    .foregroundColor(.tertiaryText)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 10)], spacing: 10) {
                ForEach(suggestions, id: \.self) { name in
                    Button { copy(name) } label: {
                        HStack(spacing: 10) {
                            Text(name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primaryText)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: copiedName == name ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(copiedName == name ? .green : .tertiaryText)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(copiedName == name ? Color.green.opacity(0.45) : Color.divider))
                    }
                    .buttonStyle(.plain)
                    .help("Copy \(name)")
                }
            }
        }
    }

    private func addCustomTags() {
        let additions = customTag.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        selectedTags.formUnion(additions)
        customTag = ""
        customTagFocused = true
    }

    private func nextWorld() {
        variation += 1
        let tags = selectedTags.isEmpty ? ["Surprise"] : selectedTags.sorted()
        let names = ProjectNameGenerator.generate(vibe: "", tags: tags, variation: variation)
        history.add(ProjectNameWorld(tags: tags, suggestions: names))
        copiedName = nil
    }

    private func previousWorld() {
        _ = history.goBack()
        copiedName = nil
    }

    private func copy(_ name: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(name, forType: .string)
        copiedName = name
    }
}
