import AppKit
import Combine

public enum ChannelMacroMode: String, CaseIterable, Identifiable {
    case pasteClipboard = "Paste Copied Plugin (⌘V)"
    case searchAndInsert = "Search & Insert Device (⌘F)"

    public var id: String { rawValue }

    public var subtitle: String {
        switch self {
        case .pasteClipboard:
            return "Copies your selected VST/device across channels with exact current settings"
        case .searchAndInsert:
            return "Searches Ableton browser and loads the specified plugin on each channel"
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
    @Published public var channelCount: Int = 8
    @Published public var pluginSearchQuery: String = "Utility"

    @Published public var isRunning: Bool = false
    @Published public var countdownRemaining: Int? = nil
    @Published public var currentChannel: Int = 0
    @Published public var statusMessage: String = "Ready"
    @Published public var lastRunSummary: String? = nil

    private var activeTask: Task<Void, Never>? = nil
    private var isCancelled: Bool = false

    public init() {
        checkEnvironment()
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

        guard channelCount > 0 else {
            statusMessage = "Please select at least 1 channel."
            return
        }

        isRunning = true
        isCancelled = false
        currentChannel = 0
        lastRunSummary = nil

        activeTask = Task { [weak self] in
            guard let self else { return }

            // 1. Initial 2-second countdown for the user
            for countdown in (1...2).reversed() {
                if self.isCancelled { break }
                self.countdownRemaining = countdown
                self.statusMessage = "Switching to Ableton Live in \(countdown)… Click starting track in Live"
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

            // 3. Execution loop across channels
            let total = self.channelCount
            let pacingDelay = self.pacing.stepDelaySeconds
            let dirCode = self.direction.keyCode
            let currentMode = self.mode
            let searchQuery = self.pluginSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

            let startTime = CFAbsoluteTimeGetCurrent()

            for step in 1...total {
                if self.isCancelled { break }

                self.currentChannel = step
                self.statusMessage = "Applying to channel \(step) of \(total)…"

                if currentMode == .pasteClipboard {
                    // Paste (Cmd+V)
                    await self.sendKeystrokeCmdV()
                } else {
                    // Search & Insert (Cmd+F -> type query -> Down Arrow -> Return)
                    await self.sendSearchAndInsert(query: searchQuery)
                }

                // Pacing delay after paste/insert
                try? await Task.sleep(nanoseconds: UInt64(pacingDelay * 1_000_000_000))

                if self.isCancelled { break }

                // Move to next channel if not on last channel
                if step < total {
                    await self.sendKeyCode(dirCode)
                    // Pacing delay after navigation
                    try? await Task.sleep(nanoseconds: UInt64(pacingDelay * 0.8 * 1_000_000_000))
                }
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            if self.isCancelled {
                self.finishRun(summary: "Stopped at channel \(self.currentChannel) of \(total).")
            } else {
                let formattedTime = String(format: "%.1f", elapsed)
                let summary = "✓ Successfully added across \(total) channels in \(formattedTime)s"
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
