import AppKit
import Carbon.HIToolbox

/// Registers a system-wide F1 hotkey that triggers the Ableton auto-version
/// and export script whenever goodvibrations HQ is running.
///
/// The hotkey works even when Ableton Live is in the foreground — that is the
/// whole point: press F1 in your session and the export happens automatically.
///
/// Enable or disable with the toggle in Settings → Ableton Export Hotkey.
@MainActor
final class GlobalHotkeyManager: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            isEnabled ? install() : uninstall()
        }
    }
    @Published private(set) var lastResult: String?

    private static let enabledKey = "abletonExportHotkeyEnabled"
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        if isEnabled { install() }
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    // MARK: - Install / Uninstall

    private func install() {
        guard globalMonitor == nil else { return }
        // Global monitor fires when the app is NOT the key application (i.e.
        // when Ableton Live is in front). Local monitor fires when HQ itself
        // is in front, so we install both.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        // Also catch it if the user presses F1 while HQ is focused.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true { return nil }
            return event
        }
        AccountDiagnostics.record("Ableton export hotkey (F1) installed")
    }

    private func uninstall() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        AccountDiagnostics.record("Ableton export hotkey (F1) uninstalled")
    }

    // MARK: - Public trigger (for Tools Hub button)

    func triggerExport() {
        Task { await runExport() }
    }

    // MARK: - Key handler

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard event.keyCode == UInt16(kVK_F1),
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else {
            return false
        }
        Task { await runExport() }
        return true
    }

    // MARK: - Script execution

    private func runExport() async {
        lastResult = nil
        AccountDiagnostics.record("F1 pressed — launching Ableton export script")

        let scriptPath = locateScript()
        guard let scriptPath else {
            let msg = "Could not locate ableton_version_export.py"
            lastResult = msg
            AccountDiagnostics.record(msg)
            sendNotification(title: "goodvibrations HQ", body: msg)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptPath]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            let msg = "Failed to launch export script: \(error.localizedDescription)"
            lastResult = msg
            AccountDiagnostics.record(msg)
            sendNotification(title: "goodvibrations HQ", body: msg)
            return
        }

        // Wait off the main actor so we don't block the UI.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let success = process.terminationStatus == 0
        let summary = success
            ? "Export triggered successfully"
            : "Export script finished with errors"
        lastResult = output.isEmpty ? summary : output
        AccountDiagnostics.record("\(summary): \(output.prefix(200))")
    }

    // MARK: - Locate the Python script

    /// Searches for the script in the most likely locations:
    /// 1. Inside the app bundle (bundled with the release build).
    /// 2. Next to the app bundle (development layout).
    /// 3. The repository Scripts/ folder (source checkout).
    private func locateScript() -> String? {
        let scriptName = "ableton_version_export.py"

        // 1. Inside the running app bundle
        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/\(scriptName)")
        if FileManager.default.fileExists(atPath: bundled.path) {
            return bundled.path
        }

        // 2. Adjacent Scripts/ folder (development: running from .build/)
        let repoRoot = Bundle.main.bundleURL          // .build/release/demos
            .deletingLastPathComponent()               // .build/release
            .deletingLastPathComponent()               // .build
            .deletingLastPathComponent()               // repo root
        let devPath = repoRoot.appendingPathComponent("Scripts/\(scriptName)")
        if FileManager.default.fileExists(atPath: devPath.path) {
            return devPath.path
        }

        // 3. Hard-coded development fallback
        let fallback = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/DemoPlayer/Scripts/\(scriptName)").path
        if FileManager.default.fileExists(atPath: fallback) {
            return fallback
        }

        return nil
    }

    // MARK: - Notification helper

    private func sendNotification(title: String, body: String) {
        let escaped = body.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(escaped)\" with title \"\(title)\""
        Process.launchedProcess(
            launchPath: "/usr/bin/osascript",
            arguments: ["-e", script]
        )
    }
}
