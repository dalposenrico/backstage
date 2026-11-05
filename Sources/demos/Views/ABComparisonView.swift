import SwiftUI
import AVFoundation

struct ABComparisonView: View {
    var embeddedProject: Project? = nil
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var references: ReferenceStore
    @EnvironmentObject var comparisonMarkers: ComparisonMarkerStore
    @EnvironmentObject private var globalHotkey: GlobalHotkeyManager
    @Environment(\.openWindow) private var openWindow
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
    @State private var isGainMatching = false
    @AppStorage("abComparisonBeatGrid") private var beatGridEnabled = true

    private var currentProject: Project? {
        embeddedProject ?? store.selectedProject ?? store.currentOpenProject ?? store.recentProjects.first
    }

    private var comparisonPlayer: ComparisonAudioPlayer {
        store.comparisonAudioPlayer
    }

    var body: some View {
        Group {
            if let project = currentProject {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        header(project)
                        matchingControls(project)
                        Divider().overlay(Color.white.opacity(0.10))
                        HStack(spacing: 0) {
                            sourceWaveforms(project)
                            Divider().overlay(Color.white.opacity(0.10))
                            sectionInspector(project)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider().overlay(Color.white.opacity(0.10))
                        assemblyRail(project)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider().overlay(Color.white.opacity(0.15))
                    ComparisonPlayerBarView(
                        controller: comparisonPlayer,
                        sourcesOverride: sources(project),
                        loudnessResultsOverride: results,
                        markersOverride: comparisonMarkers.markers(for: project)
                    )
                    .frame(height: 56)
                    .layoutPriority(10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    let s = store
                    comparisonPlayer.onStartPlayback = {
                        s.audioPlayer.pause()
                    }
                    let all = sources(project)
                    comparisonPlayer.sources = all
                    comparisonPlayer.markers = comparisonMarkers.markers(for: project)
                    comparisonPlayer.loudnessResults = results
                    comparisonPlayer.prewarm(sources: all)
                    if comparisonPlayer.activeSource == nil, let first = all.first {
                        comparisonPlayer.switchTo(
                            first,
                            allSources: all,
                            loudnessResults: results,
                            keepPosition: false,
                            playImmediately: false
                        )
                    }
                    resetAnalysis(project)
                    Task {
                        await importAbletonMarkers(into: project, userInitiated: false)
                    }
                }
                .onDisappear {
                    if embeddedProject == nil {
                        comparisonPlayer.stop()
                    }
                }
                .onChange(of: project.id) { _, _ in
                    selectedMarkerID = nil
                    markerStatus = ""
                    let all = sources(project)
                    comparisonPlayer.sources = all
                    comparisonPlayer.markers = comparisonMarkers.markers(for: project)
                    comparisonPlayer.loudnessResults = results
                    comparisonPlayer.prewarm(sources: all)
                    if let first = all.first {
                        comparisonPlayer.switchTo(
                            first,
                            allSources: all,
                            loudnessResults: results,
                            keepPosition: false,
                            playImmediately: false
                        )
                    }
                    resetAnalysis(project)
                    Task {
                        await importAbletonMarkers(into: project, userInitiated: false)
                    }
                }
                .onKeyPress(.space) {
                    let all = sources(project)
                    let loopMarker = selectedMarker(for: project)
                    let selectedRange = comparisonPlayer.sectionMode
                        ? loopMarker?.range(for: comparisonPlayer.activeSource?.url.path ?? "", legacySourcePath: project.sortedTracks.first?.url.path)
                        : nil
                    comparisonPlayer.togglePlayPause(allSources: all, loudnessResults: results, sectionRange: selectedRange)
                    return .handled
                }
                .onKeyPress(.tab) {
                    let all = sources(project)
                    let loopMarker = selectedMarker(for: project)
                    let selectedRange = comparisonPlayer.sectionMode
                        ? loopMarker?.range(for: comparisonPlayer.activeSource?.url.path ?? "", legacySourcePath: project.sortedTracks.first?.url.path)
                        : nil
                    comparisonPlayer.toggleAB(allSources: all, loudnessResults: results, sectionRange: selectedRange)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    let all = sources(project)
                    let loopMarker = selectedMarker(for: project)
                    let selectedRange = comparisonPlayer.sectionMode
                        ? loopMarker?.range(for: comparisonPlayer.activeSource?.url.path ?? "", legacySourcePath: project.sortedTracks.first?.url.path)
                        : nil
                    comparisonPlayer.switchPrevious(allSources: all, loudnessResults: results, sectionRange: selectedRange)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    let all = sources(project)
                    let loopMarker = selectedMarker(for: project)
                    let selectedRange = comparisonPlayer.sectionMode
                        ? loopMarker?.range(for: comparisonPlayer.activeSource?.url.path ?? "", legacySourcePath: project.sortedTracks.first?.url.path)
                        : nil
                    comparisonPlayer.switchNext(allSources: all, loudnessResults: results, sectionRange: selectedRange)
                    return .handled
                }
                .focusable()
            } else {
                Text("Select a project to compare audio").foregroundColor(.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if embeddedProject != nil {
                Button {
                    openWindow(id: "ab-compare")
                    WindowPresenter.showABCompare()
                } label: {
                    Label("POPOUT WINDOW", systemImage: "macwindow.on.rectangle")
                }
                .buttonStyle(IndustrialButtonStyle())
                .help("Open Versions in a separate window")
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
            Button { Task { await importAbletonMarkers(into: project, userInitiated: true) } } label: {
                if isImportingMarkers {
                    ProgressView().controlSize(.small)
                } else {
                    Label("IMPORT LOCATORS", systemImage: "square.and.arrow.down")
                }
            }
            .buttonStyle(IndustrialButtonStyle())
            .disabled(isImportingMarkers || project.newestAbletonVersion == nil || project.sortedTracks.isEmpty)
            .help("Import locators from the newest Ableton set")
            Button { references.addReferences(to: project) } label: {
                Label("REFERENCE", systemImage: "plus")
            }
            .buttonStyle(IndustrialButtonStyle())

            Button {
                if globalHotkey.isRunningExport {
                    globalHotkey.cancelExport()
                } else if store.openingAbletonProject != nil {
                    store.dismissAbletonOpeningAlert()
                } else {
                    store.openAndExport(project)
                }
            } label: {
                if isExportingThisProject(project) {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small)
                        Text(store.openingAbletonProject?.phase == .opening ? "OPENING…" : "CANCEL EXPORT")
                    }
                } else {
                    Label("FAST EXPORT", systemImage: "bolt.fill")
                }
            }
            .buttonStyle(IndustrialButtonStyle(accent: true))
            .disabled(project.newestAbletonVersion == nil)
            .help(isExportingThisProject(project) ? "Export in progress — click to cancel / reset" : "Open in Ableton Live (waits for save dialog if needed) and automatically export a new version")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(hex: "181A1D"))
    }

    private func isExportingThisProject(_ project: Project) -> Bool {
        if let opening = store.openingAbletonProject,
           opening.matchesLoadedProject(folderURL: project.folderURL),
           opening.autoExportOnReady {
            return true
        }
        if globalHotkey.isRunningExport && store.isCurrentOpenProject(project) {
            return true
        }
        return false
    }

    private func sourceWaveforms(_ project: Project) -> some View {
        let allSources = sources(project)
        return ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(Array(allSources.enumerated()), id: \.element.url) { index, source in
                    let letter = ComparisonAudioPlayer.versionLetter(for: index)
                    CompareWaveformRow(
                        source: source,
                        letter: letter,
                        samples: waveforms[source.url.path] ?? [],
                        loudness: results[source.url.path],
                        isActive: comparisonPlayer.activeSource?.url.path == source.url.path,
                        isLoading: waveformLoading.contains(source.url.path),
                        timeline: comparisonPlayer.timeline,
                        duration: audioDurations[source.url.path] ?? 0,
                        bpm: project.bpm,
                        beatGridEnabled: beatGridEnabled,
                        markers: comparisonMarkers.markers(for: project),
                        legacySourcePath: project.sortedTracks.first?.url.path,
                        selectedMarkerID: selectedMarkerID,
                        gainDB: comparisonPlayer.gainDB(for: source.url.path),
                        onGainChanged: { newGain in
                            comparisonPlayer.setGainDB(newGain, for: source.url.path)
                        },
                        onResetGain: {
                            comparisonPlayer.resetGain(for: source.url.path)
                        },
                        onAudition: { fraction in audition(source, at: fraction) },
                        onSwitchAtPlayhead: { switchAtPlayhead(to: source) },
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
        let all = sources(project)
        let hasGains = all.contains { comparisonPlayer.gainDB(for: $0.url.path) != 0 }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // GAIN MATCH action button with loading state
                Button {
                    Task {
                        await triggerGainMatch(for: project)
                    }
                } label: {
                    HStack(spacing: 5) {
                        if isGainMatching {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.65)
                            Text("MATCHING…")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "FF9F0A"))
                        } else {
                            Image(systemName: hasGains ? "equal.circle.fill" : "equal.circle")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(hasGains ? Color(hex: "FF9F0A") : Color.white.opacity(0.85))
                            Text("GAIN MATCH")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundColor(hasGains ? Color(hex: "FF9F0A") : Color.white)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4.5)
                            .fill(hasGains ? Color(hex: "FF9F0A").opacity(0.18) : Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4.5)
                            .stroke(hasGains ? Color(hex: "FF9F0A") : Color.white.opacity(0.18), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isGainMatching)
                .help("Analyze LUFS and set each track's volume fader so loudness matches evenly")

                if hasGains {
                    Button {
                        comparisonPlayer.resetAllGains(for: all)
                    } label: {
                        Text("RESET")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3.5)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 3.5))
                    }
                    .buttonStyle(.plain)
                    .help("Reset all volume faders to 0.0 dB")
                }

                Toggle("BEAT GRID", isOn: $beatGridEnabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .disabled(project.bpm == nil)
                    .help(project.bpm == nil
                        ? "Set the project BPM to use the beat grid"
                        : "Snap section markers to beats; grid bars assume 4/4")

                Spacer()

                Picker("Range", selection: Binding(
                    get: { comparisonPlayer.sectionMode },
                    set: { comparisonPlayer.sectionMode = $0 }
                )) {
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

    private func triggerGainMatch(for project: Project) async {
        isGainMatching = true
        defer { isGainMatching = false }

        let all = sources(project)
        for src in all {
            if results[src.url.path] == nil {
                if let res = await LoudnessAnalyzer.analyze(src.url) {
                    results[src.url.path] = res
                    comparisonPlayer.loudnessResults[src.url.path] = res
                }
            }
        }

        try? await Task.sleep(nanoseconds: 180_000_000)

        comparisonPlayer.applyGainMatch(with: results, sources: all)
    }

    private func audition(_ source: CompareSource, at clickedFraction: Double, marker: ComparisonMarker? = nil) {
        guard let project = currentProject else { return }
        let duration = audioDurations[source.url.path] ?? audioDuration(source.url)
        let loopMarker: ComparisonMarker? = marker ?? selectedMarker(for: project)
        let selectedRange = comparisonPlayer.sectionMode
            ? loopMarker?.range(for: source.url.path, legacySourcePath: project.sortedTracks.first?.url.path)
            : nil
        let fraction = selectedRange?.lowerBound ?? min(max(clickedFraction, 0), 1)
        let start = duration * fraction

        let all = sources(project)
        comparisonPlayer.switchTo(
            source,
            allSources: all,
            loudnessResults: results,
            keepPosition: false,
            specifiedPosition: start,
            sectionRange: selectedRange,
            playImmediately: true
        )
    }

    private func switchAtPlayhead(to source: CompareSource, marker: ComparisonMarker? = nil) {
        guard let project = currentProject else { return }
        let loopMarker: ComparisonMarker? = marker ?? selectedMarker(for: project)
        let selectedRange = comparisonPlayer.sectionMode
            ? loopMarker?.range(for: source.url.path, legacySourcePath: project.sortedTracks.first?.url.path)
            : nil
        let all = sources(project)
        comparisonPlayer.switchTo(
            source,
            allSources: all,
            loudnessResults: results,
            keepPosition: true,
            sectionRange: selectedRange,
            playImmediately: true
        )
    }

    private func addItem(_ kind: ComparisonItemKind, to project: Project) {
        let all = sources(project)
        let sourcePath = comparisonPlayer.activeSource?.url.path ?? all.first?.url.path
        let position = comparisonPlayer.activeSource == nil ? 0.5 : comparisonPlayer.timeline.progress
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
    private func importAbletonMarkers(into project: Project, userInitiated: Bool = false) async {
        guard let setURL = project.newestAbletonVersion?.url else {
            if userInitiated { markerStatus = "Need an Ableton set file (.als)" }
            return
        }

        var resolvedBpm = project.bpm
        if resolvedBpm == nil {
            resolvedBpm = await Task.detached(priority: .utility) {
                AbletonProjectInspector.readTempo(from: setURL)
            }.value
        }

        guard let bpm = resolvedBpm, bpm > 0 else {
            if userInitiated { markerStatus = "Tempo unavailable in Ableton set" }
            return
        }

        let allSources = sources(project)
        guard !allSources.isEmpty else {
            if userInitiated { markerStatus = "No audio versions to align with" }
            return
        }

        isImportingMarkers = true
        let locators = await Task.detached(priority: .utility) {
            AbletonProjectInspector.readLocators(from: setURL)
        }.value

        guard !locators.isEmpty else {
            isImportingMarkers = false
            if userInitiated { markerStatus = "No Ableton locators found in set" }
            return
        }

        var sourceDurations: [String: Double] = [:]
        for src in allSources {
            let dur = audioDurations[src.url.path] ?? audioDuration(src.url)
            if dur > 0 {
                sourceDurations[src.url.path] = dur
            }
        }

        let baseDuration = (project.sortedTracks.first?.url.path).flatMap { sourceDurations[$0] }
            ?? sourceDurations.values.first ?? 0
        guard baseDuration > 0 else {
            isImportingMarkers = false
            if userInitiated { markerStatus = "Couldn't read audio duration" }
            return
        }

        let candidates = locators.compactMap { locator -> (fraction: Double, locator: AbletonLocator, sourceFractions: [String: Double])? in
            let locatorSeconds = locator.timeInBeats * (60.0 / bpm)
            let baseFraction = locatorSeconds / baseDuration
            guard baseFraction >= 0, baseFraction <= 1.05 else { return nil }

            var perSource: [String: Double] = [:]
            for (path, dur) in sourceDurations {
                let frac = locatorSeconds / dur
                if frac >= 0 && frac <= 1.05 {
                    perSource[path] = min(max(frac, 0), 1)
                }
            }

            return (fraction: min(max(baseFraction, 0), 1), locator: locator, sourceFractions: perSource)
        }

        let count = comparisonMarkers.importAbleton(candidates, into: project)
        comparisonPlayer.markers = comparisonMarkers.markers(for: project)
        isImportingMarkers = false
        if count > 0 {
            markerStatus = "Loaded \(count) Ableton marker\(count == 1 ? "" : "s")"
        } else if userInitiated {
            markerStatus = "Ableton locators already loaded"
        }
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
        .padding(.vertical, items.isEmpty ? 6 : 8)
        .frame(height: items.isEmpty ? 36 : 52)
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
                startFraction: comparisonPlayer.sectionMode ? sectionStart : 0,
                endFraction: comparisonPlayer.sectionMode ? sectionEnd : 1
            )
            guard generation == analysisGeneration else { return }
            analyzing.remove(source.url.path)
            results[source.url.path] = result
            comparisonPlayer.loudnessResults[source.url.path] = result
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

private struct CompareWaveformRow: View {
    let source: CompareSource
    let letter: String
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
    let gainDB: Float
    let onGainChanged: (Float) -> Void
    let onResetGain: () -> Void
    let onAudition: (Double) -> Void
    let onSwitchAtPlayhead: () -> Void
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
                HStack(alignment: .center, spacing: 8) {
                    // A/B switch button at current playhead
                    Button(action: onSwitchAtPlayhead) {
                        HStack(spacing: 3.5) {
                            Text(letter)
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundColor(isActive ? .black : Color(hex: "FF9F0A"))

                            if isActive {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundColor(.black)
                            }
                        }
                        .frame(width: isActive ? 34 : 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 4.5)
                                .fill(isActive ? Color(hex: "FF9F0A") : Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4.5)
                                .stroke(isActive ? Color(hex: "FF9F0A") : Color.white.opacity(0.18), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(isActive ? "Currently active version" : "Switch to \(letter): \(source.name) at current playhead")

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Image(systemName: source.kind == "Reference" ? "scope" : "waveform")
                                .foregroundColor(isActive ? Color(hex: "FF9F0A") : Color.white.opacity(0.38))
                                .font(.system(size: 10))
                            Text(source.name)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(isActive ? .white : Color.white.opacity(0.85))
                                .lineLimit(1)
                        }
                        Text(metadata)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.tertiaryText)
                            .lineLimit(1)
                        Text(timestamp)
                            .font(.system(size: 8.5))
                            .foregroundColor(.secondaryText)
                            .lineLimit(1)
                            .help(source.exportedAt?.fullDateTime ?? "File date unavailable")
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onSwitchAtPlayhead()
                }

                // Per-track volume fader
                HStack(spacing: 6) {
                    Image(systemName: abs(gainDB) < 0.05 ? "speaker.wave.2" : (gainDB < -12 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"))
                        .font(.system(size: 8.5))
                        .foregroundColor(abs(gainDB) >= 0.05 ? Color(hex: "FF9F0A") : Color.white.opacity(0.35))
                        .frame(width: 10)

                    Slider(
                        value: Binding(
                            get: { Double(gainDB) },
                            set: { onGainChanged(Float($0)) }
                        ),
                        in: -24.0...6.0,
                        step: 0.1
                    )
                    .controlSize(.mini)
                    .tint(Color(hex: "FF9F0A"))

                    Text(gainText)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(abs(gainDB) >= 0.05 ? Color(hex: "FF9F0A") : Color.white.opacity(0.55))
                        .frame(width: 48, alignment: .trailing)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            onResetGain()
                        }
                        .help("Double-click to reset volume to 0.0 dB")
                }
            }
            .frame(width: 245, alignment: .leading)

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
                            hoverFraction: hoverFraction,
                            sectionMarkers: markers.compactMap { $0.position(for: source.url.path, legacySourcePath: legacySourcePath) }
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
                                    x: min(max(CGFloat(position) * geometry.size.width, 16), geometry.size.width - 16),
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
        .frame(height: 92)
        .background(
            Rectangle().fill(isActive ? Color(hex: "1B1E21") : Color(hex: "151719"))
        )
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.065)).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(source.name), \(metadata)")
        .accessibilityHint("Click the waveform to play from that position")
    }

    private var gainText: String {
        if abs(gainDB) < 0.05 {
            return "0.0 dB"
        } else if gainDB > 0 {
            return String(format: "+%.1f dB", gainDB)
        } else {
            return String(format: "%.1f dB", gainDB)
        }
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
                HStack(spacing: 3) {
                    Text(String(format: "%02d", number))
                    if !marker.title.isEmpty && marker.title != "New marker" {
                        Text(marker.title.uppercased())
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .padding(.horizontal, 4)
                .frame(height: 14)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 2))

                Rectangle()
                    .fill(color.opacity(isSelected ? 1 : 0.74))
                    .frame(width: isSelected ? 2 : 1, height: 42)
            }
            .frame(height: 56, alignment: .top)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.white.opacity(isSelected ? 0.8 : 0), lineWidth: 1)
            )
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
        .help("Click to audition; drag to move marker \(marker.title)")
        .accessibilityLabel("Marker \(number), \(marker.title)")
        .accessibilityHint("Drag horizontally to move, click to audition")
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
    var accent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 9)
            .frame(height: 26)
            .foregroundColor(configuration.isPressed ? .black : (accent ? Color(hex: "FF9F0A") : .white))
            .background(configuration.isPressed ? Color(hex: "FF9F0A") : (accent ? Color(hex: "FF9F0A").opacity(0.14) : Color.white.opacity(0.045)))
            .overlay(Rectangle().stroke(accent ? Color(hex: "FF9F0A").opacity(0.45) : Color.white.opacity(configuration.isPressed ? 0 : 0.18)))
    }
}
