import SwiftUI
import AppKit

struct SampleHealthAuditorView: View {
    let arrangement: AbletonArrangement
    let project: Project
    @State private var filterMissingOnly = false
    @State private var searchText = ""

    init(arrangement: AbletonArrangement, project: Project) {
        self.arrangement = arrangement
        self.project = project
    }

    private var allSamples: [AbletonSampleRef] {
        var unique = [String: AbletonSampleRef]()
        for sample in arrangement.sampleRefs {
            if unique[sample.id] == nil {
                unique[sample.id] = sample
            }
        }
        return Array(unique.values).sorted { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }
    }

    private var displayedSamples: [AbletonSampleRef] {
        allSamples.filter { sample in
            if filterMissingOnly && !sample.isMissing { return false }
            if !searchText.isEmpty {
                return sample.fileName.localizedCaseInsensitiveContains(searchText) ||
                    (sample.relativePath?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
            return true
        }
    }

    private var missingCount: Int {
        allSamples.filter(\.isMissing).count
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header stats
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(missingCount > 0 ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    Text(missingCount > 0 ? "\(missingCount) missing samples" : "All \(allSamples.count) samples collected & present")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(missingCount > 0 ? .orange : .primaryText)
                }

                Spacer()

                Toggle("Missing only", isOn: $filterMissingOnly)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .foregroundColor(.secondaryText)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(.tertiaryText)
                    TextField("Search samples...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.sidebarBg, in: RoundedRectangle(cornerRadius: 6))
                .frame(width: 180)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.sidebarBg.opacity(0.7))

            Divider().background(Color.divider)

            if displayedSamples.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundColor(.tertiaryText)
                    Text("No samples found")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(displayedSamples) { sample in
                            sampleRow(sample)
                            Divider().background(Color.white.opacity(0.04))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func sampleRow(_ sample: AbletonSampleRef) -> some View {
        HStack(spacing: 10) {
            Image(systemName: sample.isMissing ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundColor(sample.isMissing ? .orange : .green)
                .font(.system(size: 11))

            VStack(alignment: .leading, spacing: 2) {
                Text(sample.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primaryText)
                    .lineLimit(1)

                if let rel = sample.relativePath {
                    Text(rel)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.tertiaryText)
                        .lineLimit(1)
                } else if let abs = sample.absolutePath {
                    Text(abs)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.tertiaryText)
                        .lineLimit(1)
                }
            }

            Spacer()

            if !sample.isMissing, let path = sample.absolutePath ?? resolvedRelativePath(sample.relativePath) {
                let fileURL = URL(fileURLWithPath: path)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundColor(.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Reveal sample in Finder")
                .onDrag {
                    NSItemProvider(contentsOf: fileURL) ?? NSItemProvider()
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func resolvedRelativePath(_ rel: String?) -> String? {
        guard let rel else { return nil }
        let url = project.folderURL.appendingPathComponent(rel)
        return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
    }
}
