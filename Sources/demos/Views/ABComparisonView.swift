import SwiftUI
import AVFoundation

struct ABComparisonView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var references: ReferenceStore
    @EnvironmentObject var comparisonMarkers: ComparisonMarkerStore
    @State private var activePath = ""
    @State private var gainMatch = true
    @State private var sectionMode = false
    @State private var sectionStart = 0.40
    @State private var sectionEnd = 0.60
    @State private var results: [String: LoudnessResult] = [:]
    @State private var analyzing: Set<String> = []
    @State private var waveforms: [String: [SpectralWaveformSample]] = [:]
    @State private var waveformLoading: Set<String> = []
    @State private var audioDurations: [String: Double] = [:]
    @State private var analysisGeneration = UUID()
    @State private var analysisRefreshTask: Task<Void, Never>?
    @State private var selectedMarkerID: UUID?
    @State private var isImportingMarkers = false
    @State private var markerStatus = ""
    @AppStorage("abComparisonBeatGrid") private var beatGridEnabled = true

    var body: some View {
        Group {
            if let project = store.selectedProject {
                VStack(alignment: .leading, spacing: 0) {
                    header(project)
                    matchingControls(project)
                    Divider().overlay(Color.white.opacity(0.10))
                    HStack(spacing: 0) {
                        sourceWaveforms(project)
                        Divider().overlay(Color.white.opacity(0.10))
                        sectionInspector(project)
                    }
                    Divider().overlay(Color.white.opacity(0.10))
                    assemblyRail(project)
                }
                .onAppear { resetAnalysis(project) }
                .onChange(of: project.id) { _, _ in
                    selectedMarkerID = nil
                    markerStatus = ""
                    resetAnalysis(project)
                }
            } else {
                Text("Select a project to compare audio").foregroundColor(.secondaryText)
            }
        }
        .frame(minWidth: 860, minHeight: 600)
        .background(Color(hex: "111315"))
        .preferredColorScheme(.dark)
    }

    private func header(_ project: Project) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("VERSIONS")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                Text(project.name.uppercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.48))
            }
            Spacer()
            if !markerStatus.isEmpty {
                Text(markerStatus.uppercased())
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(hex: "FF9F0A"))
                    .transition(.opacity)
            }
            Button { addItem(.marker, to: project) } label: {
                Label("NEW MARKER", systemImage: "mappin")
            }
            .buttonStyle(IndustrialButtonStyle())
            .help("Add a single point for a transition, note, or navigation")
            Button { addItem(.section, to: project) } label: {
                Label("NEW SECTION", systemImage: "selection.pin.in.out")
            }
            .buttonStyle(IndustrialButtonStyle())
            .help("Add a resizable range for looping and assembly")
            Button { Task { await importAbletonMarkers(into: project) } } label: {
                if isImportingMarkers {
                    ProgressView().controlSize(.small)
                } else {
                    Label("IMPORT LOCATORS", systemImage: "square.and.arrow.down")
                }
            }
            .buttonStyle(IndustrialButtonStyle())
            .disabled(isImportingMarkers || project.newestAbletonVersion == nil || project.bpm == nil || project.sortedTracks.isEmpty)
            .help("Import locators from the newest Ableton set")
            Button { references.addReferences(to: project) } label: {
                Label("REFERENCE", systemImage: "plus")
            }
            .buttonStyle(IndustrialButtonStyle())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(hex: "181A1D"))
    }

    private func sourceWaveforms(_ project: Project) -> some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(sources(project), id: \.url) { source in
                    CompareWaveformRow(
                        source: source,
                        samples: waveforms[source.url.path] ?? [],
                        loudness: results[source.url.path],
                        isActive: activePath == source.url.path,
                        isLoading: waveformLoading.contains(source.url.path),
                        timeline: player.timeline,
                        duration: audioDurations[source.url.path] ?? 0,
                        bpm: project.bpm,
                        beatGridEnabled: beatGridEnabled,
                        markers: comparisonMarkers.markers(for: project),
                        legacySourcePath: project.sortedTracks.first?.url.path,
                        selectedMarkerID: selectedMarkerID,
                        onAudition: { fraction in audition(source, at: fraction) },
                        onSelectMarker: { marker in
                            selectedMarkerID = marker.id
                            if let position = marker.position(
                                for: source.url.path,
                                legacySourcePath: project.sortedTracks.first?.url.path
                            ) {
                                audition(source, at: position, marker: marker)
                            }
                        },
                        onPlaceSelectedMarker: { fraction in
                            placeSelectedMarker(in: source, at: fraction, project: project)
                        },
                        onMoveMarker: { marker, fraction in
                            placeMarker(marker, in: source, at: fraction, project: project)
                        },
                        onChangeRange: { marker, start, end in
                            changeRange(marker, in: source, start: start, end: end, project: project)
                        },
                        onAddToAssembly: { marker in
                            comparisonMarkers.addToAssembly(marker, sourcePath: source.url.path, for: project)
                        }
                    )
                    .task(id: source.url.path) { await prepareWaveform(source) }
                    .contextMenu {
                        if source.kind == "Reference" {
                            Button("Remove Reference") { references.remove(source.url, from: project) }
                        }
                    }
                }
            }
        }
        .background(Color(hex: "111315"))
    }

    private func matchingControls(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("GAIN MATCH", isOn: $gainMatch).toggleStyle(.checkbox)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                Toggle("BEAT GRID", isOn: $beatGridEnabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .disabled(project.bpm == nil)
                    .help(project.bpm == nil
                        ? "Set the project BPM to use the beat grid"
                        : "Snap section markers to beats; grid bars assume 4/4")
                Spacer()
                Picker("Range", selection: $sectionMode) {
                    Text("FULL").tag(false)
                    Text("SECTION LOOP").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented).frame(width: 190)
                if let bpm = project.bpm {
                    Text(String(format: "%.0f BPM", bpm))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.45))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(Color(hex: "141619"))
    }

    private func audition(_ source: CompareSource, at clickedFraction: Double, marker: ComparisonMarker? = nil) {
        let duration = audioDuration(source.url)
        let loopMarker: ComparisonMarker?
        if let marker {
            loopMarker = marker
        } else if let project = store.selectedProject {
            loopMarker = selectedMarker(for: project)
        } else {
            loopMarker = nil
        }
        let selectedRange = sectionMode
            ? loopMarker?.range(for: source.url.path, legacySourcePath: store.selectedProject?.sortedTracks.first?.url.path)
            : nil
        let fraction = selectedRange?.lowerBound ?? min(max(clickedFraction, 0), 1)
        let start = duration * fraction

        if !sectionMode, activePath == source.url.path, player.currentTrack?.url == source.url {
            player.seek(to: start)
            if !player.isPlaying { player.togglePlayPause() }
            return
        }

        let target = results.values.map(\.integratedLUFS).min()
        let gain: Float
        if gainMatch, let current = results[source.url.path], let target {
            gain = Float(min(0, target - current.integratedLUFS))
        } else {
            gain = 0
        }
        let end = selectedRange.map { duration * $0.upperBound }
        let track = Track(url: source.url, modificationDate: nil, creationDate: nil, relativeFolder: source.kind)
        player.play(track, startAt: start, gainDB: gain, loopEnd: end)
        activePath = source.url.path
    }

    private func addItem(_ kind: ComparisonItemKind, to project: Project) {
        let sourcePath = activePath.isEmpty ? sources(project).first?.url.path : activePath
        let position = activePath.isEmpty ? 0.5 : player.timeline.progress
        let marker = comparisonMarkers.add(
            to: project,
            at: position,
            sourcePath: sourcePath,
            title: kind == .marker ? "New marker" : "New section",
            kind: kind
        )
        selectedMarkerID = marker.id
        markerStatus = kind == .marker
            ? "Click each waveform to place this marker"
            : "Click each waveform to place this section"
    }

    private func placeSelectedMarker(in source: CompareSource, at fraction: Double, project: Project) {
        guard let marker = selectedMarker(for: project) else { return }
        placeMarker(marker, in: source, at: fraction, project: project)
    }

    private func placeMarker(_ marker: ComparisonMarker, in source: CompareSource, at fraction: Double, project: Project) {
        var marker = marker
        if marker.sourceFractions.isEmpty,
           let legacyPath = project.sortedTracks.first?.url.path {
            marker.setPosition(marker.fraction, for: legacyPath)
        }
        marker.setPosition(fraction, for: source.url.path)
        comparisonMarkers.update(marker, for: project)
        markerStatus = "Placed \(marker.title) in \(source.name)"
    }

    private func changeRange(
        _ marker: ComparisonMarker,
        in source: CompareSource,
        start: Double,
        end: Double,
        project: Project
    ) {
        var updated = marker
        if updated.sourceFractions.isEmpty,
           let legacyPath = project.sortedTracks.first?.url.path {
            updated.setPosition(updated.fraction, for: legacyPath)
        }
        updated.setRange(start: start, end: end, for: source.url.path)
        comparisonMarkers.update(updated, for: project)
        markerStatus = "Adjusted \(updated.title)"
    }

    @MainActor
    private func importAbletonMarkers(into project: Project) async {
        guard let setURL = project.newestAbletonVersion?.url,
              let bpm = project.bpm,
              let exportURL = project.sortedTracks.first?.url else {
            markerStatus = "Need an Ableton set, tempo, and export"
            return
        }
        let duration = audioDuration(exportURL)
        guard duration > 0 else {
            markerStatus = "Couldn’t read the export duration"
            return
        }

        isImportingMarkers = true
        let locators = await Task.detached(priority: .utility) {
            AbletonProjectInspector.readLocators(from: setURL)
        }.value
        let candidates = locators.compactMap { locator -> (fraction: Double, locator: AbletonLocator)? in
            let fraction = (locator.timeInBeats * 60 / bpm) / duration
            guard fraction >= 0, fraction <= 1.01 else { return nil }
            return (min(fraction, 1), locator)
        }
        let count = comparisonMarkers.importAbleton(candidates, into: project, sourcePath: exportURL.path)
        isImportingMarkers = false
        markerStatus = count > 0
            ? "Imported \(count) Ableton section\(count == 1 ? "" : "s")"
            : "No new Ableton locators found"
    }

    private func selectedMarker(for project: Project) -> ComparisonMarker? {
        guard let selectedMarkerID else { return nil }
        return comparisonMarkers.markers(for: project).first { $0.id == selectedMarkerID }
    }

    private func sectionInspector(_ project: Project) -> some View {
        Group {
            if let marker = selectedMarker(for: project) {
                selectedSectionInspector(marker, project: project)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ITEM INSPECTOR")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                    Spacer()
                    Image(systemName: "selection.pin.in.out")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(Color.white.opacity(0.28))
                    Text("SELECT A MARKER OR SECTION")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    Text("Markers are single points. Sections are ranges with draggable edges for looping and assembly.")
                        .font(.system(size: 10))
                        .foregroundColor(Color.white.opacity(0.44))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(14)
            }
        }
        .frame(width: 260)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(hex: "181A1D"))
    }

    private func selectedSectionInspector(_ marker: ComparisonMarker, project: Project) -> some View {
        let allSources = sources(project)
        let legacySourcePath = project.sortedTracks.first?.url.path
        let placedCount = allSources.filter {
            marker.position(for: $0.url.path, legacySourcePath: legacySourcePath) != nil
        }.count

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("\(marker.kind.rawValue.uppercased()) / \(placedCount):\(allSources.count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "FF9F0A"))
                    Spacer()
                    Button {
                        selectedMarkerID = nil
                        markerStatus = ""
                    } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                }

                TextField(marker.kind == .marker ? "MARKER NAME" : "SECTION NAME", text: markerTextBinding(marker, project: project, keyPath: \.title))
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .padding(.bottom, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1) }

                VStack(alignment: .leading, spacing: 6) {
                    Text("NOTES")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.45))
                    TextEditor(text: markerTextBinding(marker, project: project, keyPath: \.note))
                        .font(.system(size: 11))
                        .scrollContentBackground(.hidden)
                        .padding(7)
                        .frame(minHeight: 82)
                        .background(Color.black.opacity(0.24))
                        .overlay(Rectangle().stroke(Color.white.opacity(0.12)))
                }

                Text("VERSIONS")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.45))

                ForEach(allSources, id: \.url) { source in
                    let placed = marker.position(for: source.url.path, legacySourcePath: legacySourcePath) != nil
                    let preferred = marker.preferredSourcePaths.contains(source.url.path)
                    HStack(spacing: 6) {
                        Button {
                            var updated = marker
                            if preferred {
                                updated.preferredSourcePaths.removeAll { $0 == source.url.path }
                            } else {
                                updated.preferredSourcePaths.append(source.url.path)
                            }
                            comparisonMarkers.update(updated, for: project)
                        } label: {
                            Image(systemName: preferred ? "star.fill" : "star")
                                .foregroundColor(preferred ? Color(hex: "FF9F0A") : Color.white.opacity(0.28))
                        }
                        .buttonStyle(.plain)
                        .disabled(!placed)
                        Text(source.name)
                            .font(.system(size: 9, design: .monospaced))
                            .lineLimit(1)
                            .foregroundColor(placed ? .white : Color.white.opacity(0.28))
                        Spacer()
                        if placed, marker.kind == .section {
                            Button {
                                comparisonMarkers.addToAssembly(marker, sourcePath: source.url.path, for: project)
                            } label: {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.plain)
                            .help("Add this version of the section to the assembly rail")
                        }
                    }
                    .frame(height: 22)
                }

                Button(marker.kind == .marker ? "DELETE MARKER" : "DELETE SECTION", role: .destructive) {
                    comparisonMarkers.remove(marker, from: project)
                    selectedMarkerID = nil
                }
                .buttonStyle(IndustrialButtonStyle())
            }
            .padding(14)
        }
    }

    private func assemblyRail(_ project: Project) -> some View {
        let items = comparisonMarkers.assembly(for: project)
        let markers = comparisonMarkers.markers(for: project)
        let allSources = sources(project)

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ASSEMBLY")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                Text("MANUAL BUILD ORDER")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.35))
            }
            .frame(width: 112, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    if items.isEmpty {
                        Text("ADD A SECTION FROM THE INSPECTOR OR A REGION MENU")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.28))
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if let marker = markers.first(where: { $0.id == item.markerID }),
                           let source = allSources.first(where: { $0.url.path == item.sourcePath }) {
                            HStack(spacing: 6) {
                                Text(String(format: "%02d", index + 1))
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(hex: "FF9F0A"))
                                Button {
                                    selectedMarkerID = marker.id
                                    if let range = marker.range(for: source.url.path, legacySourcePath: project.sortedTracks.first?.url.path) {
                                        audition(source, at: range.lowerBound, marker: marker)
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(marker.title.uppercased()).font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        Text(source.name).font(.system(size: 8, design: .monospaced)).foregroundColor(Color.white.opacity(0.42))
                                    }
                                }
                                .buttonStyle(.plain)
                                Button { comparisonMarkers.moveAssemblyItem(item, by: -1, for: project) } label: { Image(systemName: "chevron.left") }
                                    .buttonStyle(.plain).disabled(index == 0)
                                Button { comparisonMarkers.moveAssemblyItem(item, by: 1, for: project) } label: { Image(systemName: "chevron.right") }
                                    .buttonStyle(.plain).disabled(index == items.count - 1)
                                Button { comparisonMarkers.removeFromAssembly(item, for: project) } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 42)
                            .background(Color.white.opacity(0.055))
                            .overlay(Rectangle().stroke(Color.white.opacity(0.12)))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(height: 66)
        .background(Color(hex: "141619"))
    }

    private func markerTextBinding(
        _ marker: ComparisonMarker,
        project: Project,
        keyPath: WritableKeyPath<ComparisonMarker, String>
    ) -> Binding<String> {
        Binding(
            get: {
                selectedMarker(for: project)?[keyPath: keyPath] ?? marker[keyPath: keyPath]
            },
            set: { value in
                guard var updated = selectedMarker(for: project) else { return }
                updated[keyPath: keyPath] = value
                comparisonMarkers.update(updated, for: project)
            }
        )
    }

    private func analyze(
        _ source: CompareSource,
        generation: UUID,
        completion: @escaping () -> Void = {}
    ) {
        if results[source.url.path] != nil { completion(); return }
        guard !analyzing.contains(source.url.path) else { return }
        analyzing.insert(source.url.path)
        Task {
            let result = await LoudnessAnalyzer.analyze(
                source.url,
                startFraction: sectionMode ? sectionStart : 0,
                endFraction: sectionMode ? sectionEnd : 1
            )
            guard generation == analysisGeneration else { return }
            analyzing.remove(source.url.path)
            results[source.url.path] = result
            completion()
        }
    }

    private func resetAnalysis(_ project: Project) {
        analysisRefreshTask?.cancel()
        let generation = UUID()
        analysisGeneration = generation
        results = [:]
        analyzing = []
        for source in sources(project) {
            analyze(source, generation: generation)
        }
    }

    private func scheduleAnalysis(for project: Project) {
        results = [:]
        analysisRefreshTask?.cancel()
        analysisRefreshTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            resetAnalysis(project)
        }
    }

    @MainActor
    private func prepareWaveform(_ source: CompareSource) async {
        guard waveforms[source.url.path] == nil, !waveformLoading.contains(source.url.path) else { return }
        waveformLoading.insert(source.url.path)
        async let sampledWaveform = WaveformSampler.spectralSamples(for: source.url)
        async let measuredDuration: Double = Task.detached(priority: .utility) {
            guard let file = try? AVAudioFile(forReading: source.url) else { return 0 }
            return Double(file.length) / file.processingFormat.sampleRate
        }.value
        let (samples, duration) = await (sampledWaveform, measuredDuration)
        waveforms[source.url.path] = samples
        audioDurations[source.url.path] = duration
        waveformLoading.remove(source.url.path)
    }

    private func sources(_ project: Project) -> [CompareSource] {
        let exports = project.tracks.map {
            CompareSource(
                url: $0.url,
                name: $0.displayName,
                kind: $0.relativeFolder.isEmpty ? "Export" : $0.relativeFolder,
                exportedAt: $0.modificationDate ?? $0.creationDate,
                isReference: false
            )
        }
        let referenceSources = references.references(for: project).map { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            return CompareSource(
                url: url,
                name: url.deletingPathExtension().lastPathComponent,
                kind: "Reference",
                exportedAt: values?.contentModificationDate ?? values?.creationDate,
                isReference: true
            )
        }
        return (exports + referenceSources).sorted {
            if $0.exportedAt != $1.exportedAt {
                return ($0.exportedAt ?? .distantPast) > ($1.exportedAt ?? .distantPast)
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func audioDuration(_ url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}

private struct CompareSource {
    let url: URL
    let name: String
    let kind: String
    let exportedAt: Date?
    let isReference: Bool
}

private struct CompareWaveformRow: View {
    let source: CompareSource
    let samples: [SpectralWaveformSample]
    let loudness: LoudnessResult?
    let isActive: Bool
    let isLoading: Bool
    @ObservedObject var timeline: PlaybackTimeline
    let duration: Double
    let bpm: Double?
    let beatGridEnabled: Bool
    let markers: [ComparisonMarker]
    let legacySourcePath: String?
    let selectedMarkerID: UUID?
    let onAudition: (Double) -> Void
    let onSelectMarker: (ComparisonMarker) -> Void
    let onPlaceSelectedMarker: (Double) -> Void
    let onMoveMarker: (ComparisonMarker, Double) -> Void
    let onChangeRange: (ComparisonMarker, Double, Double) -> Void
    let onAddToAssembly: (ComparisonMarker) -> Void
    @State private var hoverFraction: Double?

    private var playhead: Double? {
        isActive && timeline.duration > 0 ? timeline.progress : nil
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: source.kind == "Reference" ? "scope" : "waveform")
                        .foregroundColor(isActive ? Color(hex: "FF9F0A") : Color.white.opacity(0.38))
                    Text(source.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                Text(metadata)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.tertiaryText)
                    .lineLimit(1)
                Text(timestamp)
                    .font(.system(size: 9))
                    .foregroundColor(.secondaryText)
                    .lineLimit(1)
                    .help(source.exportedAt?.fullDateTime ?? "File date unavailable")
            }
            .frame(width: 220, alignment: .leading)

            GeometryReader { geometry in
                ZStack {
                    Rectangle().fill(Color(hex: "0B0D0F"))
                    if beatGridEnabled, let bpm, duration > 0 {
                        ComparisonBeatGridOverlay(duration: duration, bpm: bpm)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    if samples.isEmpty {
                        if isLoading { ProgressView().controlSize(.small) }
                    } else {
                        SpectralWaveformView(
                            samples: samples,
                            playedFraction: playhead,
                            hoverFraction: hoverFraction
                        )
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { gesture in
                                    let clickedFraction = fraction(for: gesture.location.x, width: geometry.size.width)
                                    if selectedMarkerID != nil {
                                        let placedFraction = adjustedFraction(clickedFraction)
                                        onPlaceSelectedMarker(placedFraction)
                                        onAudition(placedFraction)
                                    } else {
                                        onAudition(clickedFraction)
                                    }
                                }
                        )
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let point):
                                hoverFraction = fraction(for: point.x, width: geometry.size.width)
                            case .ended:
                                hoverFraction = nil
                            }
                        }
                        .help("Click anywhere to play this version from that position")
                    }
                    ForEach(Array(markers.enumerated()), id: \.element.id) { index, marker in
                        if let position = marker.position(for: source.url.path, legacySourcePath: legacySourcePath) {
                            if marker.kind == .section,
                               let range = marker.range(for: source.url.path, legacySourcePath: legacySourcePath) {
                                ComparisonSectionRegion(
                                    number: index + 1,
                                    marker: marker,
                                    isSelected: selectedMarkerID == marker.id,
                                    isPreferredHere: marker.preferredSourcePaths.contains(source.url.path),
                                    range: range,
                                    waveformWidth: geometry.size.width,
                                    adjustedPosition: adjustedFraction,
                                    action: { onSelectMarker(marker) },
                                    onChangeRange: { onChangeRange(marker, $0, $1) },
                                    onAddToAssembly: { onAddToAssembly(marker) }
                                )
                                .position(
                                    x: CGFloat((range.lowerBound + range.upperBound) / 2) * geometry.size.width,
                                    y: geometry.size.height / 2
                                )
                            } else {
                                ComparisonPointMarker(
                                    number: index + 1,
                                    marker: marker,
                                    isSelected: selectedMarkerID == marker.id,
                                    isPreferredHere: marker.preferredSourcePaths.contains(source.url.path),
                                    position: position,
                                    waveformWidth: geometry.size.width,
                                    adjustedPosition: adjustedFraction,
                                    action: { onSelectMarker(marker) },
                                    onMove: { onMoveMarker(marker, $0) }
                                )
                                .position(
                                    x: min(max(CGFloat(position) * geometry.size.width, 8), geometry.size.width - 8),
                                    y: geometry.size.height / 2
                                )
                            }
                        }
                    }
                }
                .overlay {
                    Rectangle()
                        .stroke(isActive ? Color(hex: "FF9F0A").opacity(0.9) : Color.white.opacity(0.10), lineWidth: isActive ? 1.5 : 1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(height: 86)
        .background(
            Rectangle().fill(isActive ? Color(hex: "1B1E21") : Color(hex: "151719"))
        )
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.065)).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(source.name), \(metadata)")
        .accessibilityHint("Click the waveform to play from that position")
    }

    private var metadata: String {
        guard let loudness else { return source.kind }
        return String(format: "%@  ·  %.1f LUFS  ·  %.1f dBFS", source.kind, loudness.integratedLUFS, loudness.samplePeakDBFS)
    }

    private var timestamp: String {
        guard let date = source.exportedAt else { return "Export date unavailable" }
        return "\(source.isReference ? "File dated" : "Exported") \(date.menuSavedDate)"
    }

    private func fraction(for x: CGFloat, width: CGFloat) -> Double {
        min(max(Double(x / max(1, width)), 0), 1)
    }

    private func adjustedFraction(_ fraction: Double) -> Double {
        guard beatGridEnabled, let bpm else { return min(max(fraction, 0), 1) }
        return ComparisonBeatGrid.snappedFraction(fraction, duration: duration, bpm: bpm)
    }
}

private struct ComparisonBeatGridOverlay: View {
    let duration: Double
    let bpm: Double

    var body: some View {
        Canvas { context, size in
            let totalBeats = duration * bpm / 60
            guard totalBeats > 0 else { return }
            let interval = ComparisonBeatGrid.visibleIntervalInBeats(
                duration: duration,
                bpm: bpm,
                width: size.width
            )
            for beat in stride(from: 0.0, through: totalBeats, by: interval) {
                let x = size.width * beat / totalBeats
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                let isPhrase = beat.truncatingRemainder(dividingBy: 16) < 0.001
                let isBar = beat.truncatingRemainder(dividingBy: 4) < 0.001
                context.stroke(
                    path,
                    with: .color(.white.opacity(isPhrase ? 0.16 : (isBar ? 0.10 : 0.055))),
                    lineWidth: isPhrase ? 1 : 0.5
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ComparisonPointMarker: View {
    let number: Int
    let marker: ComparisonMarker
    let isSelected: Bool
    let isPreferredHere: Bool
    let position: Double
    let waveformWidth: CGFloat
    let adjustedPosition: (Double) -> Double
    let action: () -> Void
    let onMove: (Double) -> Void
    @State private var dragOffset: CGFloat = 0

    private var color: Color {
        if isPreferredHere { return Color(hex: "30D158") }
        let colors = ["FF9F0A", "4DA3FF", "BF5AF2", "64D2FF", "FFD60A", "FF6482"]
        return Color(hex: colors[(number - 1) % colors.count])
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(String(format: "%02d", number))
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .frame(width: 20, height: 14)
                    .background(color)
                Rectangle()
                    .fill(color.opacity(isSelected ? 1 : 0.74))
                    .frame(width: isSelected ? 2 : 1, height: 42)
            }
            .frame(width: 22, height: 56, alignment: .top)
            .overlay(Rectangle().stroke(.white.opacity(isSelected ? 0.8 : 0), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .offset(x: dragOffset)
        .highPriorityGesture(
            DragGesture(minimumDistance: 2)
                .onChanged { gesture in
                    let proposed = position + Double(gesture.translation.width / max(1, waveformWidth))
                    let adjusted = adjustedPosition(proposed)
                    dragOffset = CGFloat(adjusted - position) * waveformWidth
                }
                .onEnded { gesture in
                    let proposed = position + Double(gesture.translation.width / max(1, waveformWidth))
                    let adjusted = adjustedPosition(proposed)
                    dragOffset = 0
                    onMove(adjusted)
                }
        )
        .help("Drag to move marker \(marker.title)")
        .accessibilityLabel("Marker \(number), \(marker.title)")
        .accessibilityHint("Drag horizontally to move")
    }
}

private struct ComparisonSectionRegion: View {
    let number: Int
    let marker: ComparisonMarker
    let isSelected: Bool
    let isPreferredHere: Bool
    let range: ClosedRange<Double>
    let waveformWidth: CGFloat
    let adjustedPosition: (Double) -> Double
    let action: () -> Void
    let onChangeRange: (Double, Double) -> Void
    let onAddToAssembly: () -> Void
    @State private var previewStart: Double?
    @State private var previewEnd: Double?

    var color: Color {
        if isPreferredHere { return Color(hex: "30D158") }
        let colors = ["FF9F0A", "4DA3FF", "BF5AF2", "64D2FF", "FFD60A", "FF6482"]
        return Color(hex: colors[(number - 1) % colors.count])
    }

    private var displayedStart: Double { previewStart ?? range.lowerBound }
    private var displayedEnd: Double { previewEnd ?? range.upperBound }
    private var baseCenter: Double { (range.lowerBound + range.upperBound) / 2 }
    private var displayedCenter: Double { (displayedStart + displayedEnd) / 2 }

    private var displayedWidth: CGFloat {
        max(30, CGFloat(displayedEnd - displayedStart) * waveformWidth)
    }

    var body: some View {
        ZStack {
            Button(action: action) {
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(color.opacity(isSelected ? 0.32 : 0.18))
                    Rectangle().stroke(color.opacity(isSelected ? 1 : 0.70), lineWidth: isSelected ? 1.5 : 1)
                    HStack(spacing: 5) {
                        Text(String(format: "%02d", number))
                            .foregroundColor(color)
                        Text(marker.title.uppercased())
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.top, 5)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .gesture(moveGesture)

            HStack {
                resizeHandle(isLeading: true)
                Spacer()
                resizeHandle(isLeading: false)
            }
        }
        .frame(width: displayedWidth, height: 54)
        .offset(x: CGFloat(displayedCenter - baseCenter) * waveformWidth)
        .contextMenu {
            Button("Add to Assembly") { onAddToAssembly() }
        }
        .help("Drag to move; drag either edge to resize \(marker.title)")
        .accessibilityLabel("Section \(number), \(marker.title)")
        .accessibilityHint("Drag horizontally to move; drag either edge to resize")
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { gesture in
                let length = range.upperBound - range.lowerBound
                let proposed = range.lowerBound + Double(gesture.translation.width / max(1, waveformWidth))
                let start = min(max(adjustedPosition(proposed), 0), 1 - length)
                previewStart = start
                previewEnd = start + length
            }
            .onEnded { gesture in
                let length = range.upperBound - range.lowerBound
                let proposed = range.lowerBound + Double(gesture.translation.width / max(1, waveformWidth))
                let start = min(max(adjustedPosition(proposed), 0), 1 - length)
                previewStart = nil
                previewEnd = nil
                onChangeRange(start, start + length)
            }
    }

    private func resizeHandle(isLeading: Bool) -> some View {
        Rectangle()
            .fill(color.opacity(isSelected ? 0.95 : 0.58))
            .frame(width: 5, height: 54)
            .contentShape(Rectangle().inset(by: -4))
            .highPriorityGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { gesture in
                        let delta = Double(gesture.translation.width / max(1, waveformWidth))
                        if isLeading {
                            previewStart = min(adjustedPosition(range.lowerBound + delta), range.upperBound - 0.01)
                            previewEnd = range.upperBound
                        } else {
                            previewStart = range.lowerBound
                            previewEnd = max(adjustedPosition(range.upperBound + delta), range.lowerBound + 0.01)
                        }
                    }
                    .onEnded { gesture in
                        let delta = Double(gesture.translation.width / max(1, waveformWidth))
                        let start = isLeading
                            ? min(adjustedPosition(range.lowerBound + delta), range.upperBound - 0.01)
                            : range.lowerBound
                        let end = isLeading
                            ? range.upperBound
                            : max(adjustedPosition(range.upperBound + delta), range.lowerBound + 0.01)
                        previewStart = nil
                        previewEnd = nil
                        onChangeRange(start, end)
                    }
            )
    }
}

private struct IndustrialButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 9)
            .frame(height: 26)
            .foregroundColor(configuration.isPressed ? .black : .white)
            .background(configuration.isPressed ? Color(hex: "FF9F0A") : Color.white.opacity(0.045))
            .overlay(Rectangle().stroke(Color.white.opacity(configuration.isPressed ? 0 : 0.18)))
    }
}
