import AppKit
import SwiftUI
import Combine

public enum ChannelMacroMode: String, CaseIterable, Identifiable {
    case pasteClipboard = "Paste Copied Plugin (⌘V)"
    case searchAndInsert = "Search & Insert Device (⌘F)"

    public var id: String { rawValue }

    public var subtitle: String {
        switch self {
        case .pasteClipboard:
            return "Copies your selected VST/device across chosen channels with exact current settings"
        case .searchAndInsert:
            return "Searches Ableton browser and loads the specified plugin on chosen channels"
        }
    }
}

public enum ChannelMacroPacing: String, CaseIterable, Identifiable {
    case relaxed = "Safe (250ms)"
    case normal = "Normal (150ms)"
    case fast = "Turbo (80ms)"

    public var id: String { rawValue }

    public var stepDelaySeconds: Double {
        switch self {
        case .relaxed: return 0.25
        case .normal: return 0.15
        case .fast: return 0.08
        }
    }
}

public enum ChannelMacroDirection: String, CaseIterable, Identifiable {
    case arrangementDown = "Arrangement View (↓ Down)"
    case sessionRight = "Session View (→ Right)"

    public var id: String { rawValue }

    public var keyCode: Int {
        switch self {
        case .arrangementDown: return 125 // Down arrow
        case .sessionRight: return 124    // Right arrow
        }
    }
}

public struct MacroTrackTarget: Identifiable, Equatable {
    public let id: String
    public let index: Int              // 1-based index (e.g. 1)
    public let name: String            // e.g. "Kick"
    public let type: AbletonTrackType  // .audio, .midi, .group
    public let colorIndex: Int
    public let devices: [String]       // existing device names
    public var isSelected: Bool

    public init(
        id: String = UUID().uuidString,
        index: Int,
        name: String,
        type: AbletonTrackType = .audio,
        colorIndex: Int = 12,
        devices: [String] = [],
        isSelected: Bool = true
    ) {
        self.id = id
        self.index = index
        self.name = name
        self.type = type
        self.colorIndex = colorIndex
        self.devices = devices
        self.isSelected = isSelected
    }

    public var color: Color {
        AbletonColorPalette.color(for: colorIndex)
    }
}

@MainActor
public final class AbletonChannelMacroEngine: ObservableObject {
    public static let shared = AbletonChannelMacroEngine()

    // MARK: - Published State
    @Published public var isAbletonRunning: Bool = false
    @Published public var abletonAppName: String? = nil
    @Published public var isAccessibilityTrusted: Bool = false

    @Published public var mode: ChannelMacroMode = .pasteClipboard
    @Published public var pacing: ChannelMacroPacing = .normal
    @Published public var direction: ChannelMacroDirection = .arrangementDown
    @Published public var pluginSearchQuery: String = "Utility"

    // Target Tracks Selection
    @Published public var loadedProjectName: String? = nil
    @Published public var loadedProjectURL: URL? = nil
    @Published public var tracks: [MacroTrackTarget] = []
    @Published public var startTrackIndex: Int = 1

    @Published public var isRunning: Bool = false
    @Published public var countdownRemaining: Int? = nil
    @Published public var currentProcessingTrack: String? = nil
    @Published public var statusMessage: String = "Ready"
    @Published public var lastRunSummary: String? = nil
    @Published public var executionLog: [String] = []

    private var activeTask: Task<Void, Never>? = nil
    private var isCancelled: Bool = false

    public init() {
        checkEnvironment()
        createDefaultTracks(count: 8)
    }

    // MARK: - Track Management

    public var selectedTracks: [MacroTrackTarget] {
        tracks.filter(\.isSelected)
    }

    public var selectedCount: Int {
        selectedTracks.count
    }

    public func createDefaultTracks(count: Int) {
        self.loadedProjectName = nil
        self.loadedProjectURL = nil
        self.tracks = (1...max(1, count)).map { idx in
            MacroTrackTarget(
                index: idx,
                name: "Track \(idx)",
                type: idx % 2 == 1 ? .audio : .midi,
                colorIndex: idx,
                devices: [],
                isSelected: true
            )
        }
        self.startTrackIndex = 1
    }

    public func loadTracks(from arrangement: AbletonArrangement, projectName: String?, fileURL: URL? = nil) {
        self.loadedProjectName = projectName
        self.loadedProjectURL = fileURL
        self.tracks = arrangement.tracks.enumerated().map { idx, track in
            MacroTrackTarget(
                id: track.id,
                index: idx + 1,
                name: track.name,
                type: track.type,
                colorIndex: track.colorIndex,
                devices: track.devices.map(\.name),
                isSelected: track.type != .group // Select audio and midi tracks by default
            )
        }
        self.startTrackIndex = tracks.first(where: \.isSelected)?.index ?? 1
    }

    public func selectAllTracks() {
        for i in tracks.indices { tracks[i].isSelected = true }
    }

    public func deselectAllTracks() {
        for i in tracks.indices { tracks[i].isSelected = false }
    }

    public func selectAudioTracksOnly() {
        for i in tracks.indices { tracks[i].isSelected = (tracks[i].type == .audio) }
    }

    public func selectMidiTracksOnly() {
        for i in tracks.indices { tracks[i].isSelected = (tracks[i].type == .midi) }
    }

    public func toggleTrack(id: String) {
        if let idx = tracks.firstIndex(where: { $0.id == id }) {
            tracks[idx].isSelected.toggle()
        }
    }

    // MARK: - Environment Checks

    public func checkEnvironment() {
        let liveApp = NSWorkspace.shared.runningApplications.first { app in
            guard let name = app.localizedName?.lowercased() else { return false }
            return name.contains("live") || app.bundleIdentifier?.lowercased().contains("ableton") == true
        }

        self.isAbletonRunning = (liveApp != nil)
        self.abletonAppName = liveApp?.localizedName

        let trusted = AXIsProcessTrusted()
        self.isAccessibilityTrusted = trusted
    }

    func refreshFromOpenSession(using projects: [Project] = []) {
        checkEnvironment()
        let snapshot = AbletonSessionDetector.snapshot()
        if let docURL = snapshot.loadedDocumentURLs.first,
           let parsed = AbletonArrangementParser.parse(from: docURL) {
            let name = docURL.deletingPathExtension().lastPathComponent
            loadTracks(from: parsed, projectName: name, fileURL: docURL)
            return
        }

        if let matched = AbletonSessionDetector.matchingProject(in: projects, loadedDocumentURLs: snapshot.loadedDocumentURLs) ?? projects.first,
           let alsURL = matched.newestAbletonVersion?.url ?? matched.versions.first?.url,
           let parsed = AbletonArrangementParser.parse(from: alsURL) {
            loadTracks(from: parsed, projectName: matched.name, fileURL: alsURL)
        }
    }

    public func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        checkEnvironment()
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Execution

    public func startMacro() {
        checkEnvironment()

        guard isAbletonRunning else {
            statusMessage = "Ableton Live is not open. Please launch your project in Live first."
            return
        }

        let selected = self.selectedTracks
        guard !selected.isEmpty else {
            statusMessage = "Please select at least 1 track to apply the plugin to."
            return
        }

        guard let firstSelected = selected.first,
              let lastSelected = selected.last else { return }

        let startIndex = firstSelected.index
        let endIndex = lastSelected.index

        isRunning = true
        isCancelled = false
        executionLog = []
        lastRunSummary = nil

        activeTask = Task { [weak self] in
            guard let self else { return }

            // 1. Initial 2-second countdown for the user
            for countdown in (1...2).reversed() {
                if self.isCancelled { break }
                self.countdownRemaining = countdown
                self.statusMessage = "Switching to Ableton Live in \(countdown)… Ensure Track #\(startIndex) ('\(firstSelected.name)') is selected in Live"
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            self.countdownRemaining = nil

            if self.isCancelled {
                self.finishRun(summary: "Cancelled before starting.")
                return
            }

            // 2. Activate Ableton Live window to front
            self.statusMessage = "Activating Ableton Live…"
            self.activateAbletonLive()
            try? await Task.sleep(nanoseconds: 400_000_000)

            if self.isCancelled {
                self.finishRun(summary: "Cancelled.")
                return
            }

            // 3. Execution loop across tracks from startIndex to endIndex
            let pacingDelay = self.pacing.stepDelaySeconds
            let dirCode = self.direction.keyCode
            let currentMode = self.mode
            let searchQuery = self.pluginSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

            let startTime = CFAbsoluteTimeGetCurrent()
            var modifiedCount = 0

            for trackNum in startIndex...endIndex {
                if self.isCancelled { break }

                guard let trackItem = self.tracks.first(where: { $0.index == trackNum }) else {
                    continue
                }

                self.currentProcessingTrack = trackItem.name

                if trackItem.isSelected {
                    self.statusMessage = "Pasting on #\(trackItem.index) '\(trackItem.name)'…"

                    if currentMode == .pasteClipboard {
                        await self.sendKeystrokeCmdV()
                    } else {
                        await self.sendSearchAndInsert(query: searchQuery)
                    }

                    modifiedCount += 1
                    self.executionLog.append("✓ #\(trackItem.index) \(trackItem.name)")
                    try? await Task.sleep(nanoseconds: UInt64(pacingDelay * 1_000_000_000))
                } else {
                    self.statusMessage = "Skipping #\(trackItem.index) '\(trackItem.name)'…"
                    self.executionLog.append("↷ Skipped #\(trackItem.index) \(trackItem.name)")
                }

                if self.isCancelled { break }

                // Move to next channel if not on last channel
                if trackNum < endIndex {
                    await self.sendKeyCode(dirCode)
                    try? await Task.sleep(nanoseconds: UInt64(pacingDelay * 0.8 * 1_000_000_000))
                }
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            if self.isCancelled {
                self.finishRun(summary: "Stopped. Applied to \(modifiedCount) of \(selected.count) selected tracks.")
            } else {
                let formattedTime = String(format: "%.1f", elapsed)
                let summary = "✓ Successfully added to \(modifiedCount) selected tracks in \(formattedTime)s"
                self.finishRun(summary: summary)
                self.postNotification(title: "Channel Plugin Runner", message: summary)
            }
        }
    }

    public func stopMacro() {
        isCancelled = true
        activeTask?.cancel()
        activeTask = nil
        finishRun(summary: "Macro stopped.")
    }

    private func finishRun(summary: String) {
        isRunning = false
        countdownRemaining = nil
        currentProcessingTrack = nil
        statusMessage = summary
        lastRunSummary = summary
    }

    // MARK: - Keystroke Automation via osascript

    private func activateAbletonLive() {
        if let liveApp = NSWorkspace.shared.runningApplications.first(where: { app in
            guard let name = app.localizedName?.lowercased() else { return false }
            return name.contains("live") || app.bundleIdentifier?.lowercased().contains("ableton") == true
        }) {
            liveApp.activate()
        }

        let script = """
        tell application "System Events"
            if (exists (first process whose name contains "Live" and background only is false)) then
                set liveProc to (first process whose name contains "Live" and background only is false)
                set frontmost of liveProc to true
            end if
        end tell
        """
        _ = runAppleScript(script)
    }

    private func sendKeystrokeCmdV() async {
        let script = """
        tell application "System Events"
            keystroke "v" using {command down}
        end tell
        """
        _ = await runAppleScriptAsync(script)
    }

    private func sendKeyCode(_ code: Int) async {
        let script = """
        tell application "System Events"
            key code \(code)
        end tell
        """
        _ = await runAppleScriptAsync(script)
    }

    private func sendSearchAndInsert(query: String) async {
        let escaped = query.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "System Events"
            keystroke "f" using {command down}
            delay 0.15
            keystroke "\(escaped)"
            delay 0.2
            key code 125 -- Down Arrow into browser results
            delay 0.1
            key code 36  -- Return to load device
        end tell
        """
        _ = await runAppleScriptAsync(script)
    }

    private func runAppleScriptAsync(_ script: String) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let pipe = Pipe()
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }.value
    }

    private func runAppleScript(_ script: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func postNotification(title: String, message: String) {
        let script = """
        display notification "\(message.replacingOccurrences(of: "\"", with: "\\\""))" with title "\(title.replacingOccurrences(of: "\"", with: "\\\""))"
        """
        _ = runAppleScript(script)
    }
}
