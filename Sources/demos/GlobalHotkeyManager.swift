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
    @Published var isRunningExport = false
    @Published private(set) var lastResult: String?

    static weak var shared: GlobalHotkeyManager?

    private static let enabledKey = "abletonExportHotkeyEnabled"
    private static let hotKeySignature = OSType(0x47564851) // 'GVHQ'
    private static let hotKeyIDF1: UInt32 = 1
    private static let hotKeyIDAlt: UInt32 = 2

    private var carbonHotKeyRefF1: EventHotKeyRef?
    private var carbonHotKeyRefAlt: EventHotKeyRef?
    private var carbonEventHandlerRef: EventHandlerRef?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    init() {
        let saved = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool
        self.isEnabled = saved ?? true
        Self.shared = self
        if isEnabled { install() }
    }

    deinit {
        if let carbonHotKeyRefF1 { UnregisterEventHotKey(carbonHotKeyRefF1) }
        if let carbonHotKeyRefAlt { UnregisterEventHotKey(carbonHotKeyRefAlt) }
        if let carbonEventHandlerRef { RemoveEventHandler(carbonEventHandlerRef) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    // MARK: - Install / Uninstall

    private func install() {
        Self.shared = self

        // 1. Carbon Global Hotkey (requires NO Accessibility permissions)
        installCarbonHotKeys()

        // 2. NSEvent monitors as fallback
        if globalMonitor == nil {
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)

            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyEvent(event)
            }
        }
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if self?.handleKeyEvent(event) == true { return nil }
                return event
            }
        }
        AccountDiagnostics.record("Ableton export hotkeys (Carbon + Cocoa: F1 / ⇧⌘E) installed")
    }

    private func installCarbonHotKeys() {
        guard carbonEventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, eventRef, _) -> OSStatus in
                guard let eventRef = eventRef else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let paramStatus = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if paramStatus == noErr && hotKeyID.signature == GlobalHotkeyManager.hotKeySignature {
                    DispatchQueue.main.async {
                        GlobalHotkeyManager.shared?.triggerExport()
                    }
                    return noErr
                }
                return OSStatus(eventNotHandledErr)
            },
            1,
            &eventType,
            nil,
            &carbonEventHandlerRef
        )

        if status != noErr {
            AccountDiagnostics.record("Failed to install Carbon hotkey handler: \(status)")
            return
        }

        // Register F1 (no modifiers)
        var f1Ref: EventHotKeyRef?
        let f1ID = EventHotKeyID(signature: Self.hotKeySignature, id: Self.hotKeyIDF1)
        let regF1 = RegisterEventHotKey(
            UInt32(kVK_F1),
            0,
            f1ID,
            GetApplicationEventTarget(),
            0,
            &f1Ref
        )
        if regF1 == noErr {
            self.carbonHotKeyRefF1 = f1Ref
        }

        // Register Cmd+Shift+E as secondary shortcut (great for keyboards where F1 needs Fn)
        var altRef: EventHotKeyRef?
        let altID = EventHotKeyID(signature: Self.hotKeySignature, id: Self.hotKeyIDAlt)
        let cmdShift = UInt32(cmdKey | shiftKey)
        let regAlt = RegisterEventHotKey(
            UInt32(kVK_ANSI_E),
            cmdShift,
            altID,
            GetApplicationEventTarget(),
            0,
            &altRef
        )
        if regAlt == noErr {
            self.carbonHotKeyRefAlt = altRef
        }
    }

    private func uninstall() {
        if let carbonHotKeyRefF1 {
            UnregisterEventHotKey(carbonHotKeyRefF1)
            self.carbonHotKeyRefF1 = nil
        }
        if let carbonHotKeyRefAlt {
            UnregisterEventHotKey(carbonHotKeyRefAlt)
            self.carbonHotKeyRefAlt = nil
        }
        if let carbonEventHandlerRef {
            RemoveEventHandler(carbonEventHandlerRef)
            self.carbonEventHandlerRef = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        AccountDiagnostics.record("Ableton export hotkeys uninstalled")
    }

    // MARK: - Public trigger (for Tools Hub button & Menu commands)

    func triggerExport() {
        Task { await runExport() }
    }

    // MARK: - Key handler (Cocoa fallback)

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let isF1 = event.keyCode == UInt16(kVK_F1)
        let isCmdShiftE = event.keyCode == UInt16(kVK_ANSI_E) && event.modifierFlags.contains([.command, .shift])

        if isF1 {
            let disallowedModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard disallowedModifiers.isEmpty else { return false }
            Task { await runExport() }
            return true
        } else if isCmdShiftE {
            Task { await runExport() }
            return true
        }
        return false
    }

    // MARK: - Script execution

    private func runExport() async {
        isRunningExport = true
        lastResult = "⚡ Running Ableton auto-export..."
        AccountDiagnostics.record("F1 pressed — launching Ableton export script")
        sendNotification(title: "goodvibrations HQ", body: "⚡ F1 triggered: Preparing Ableton auto-export...")

        let scriptPath = locateScript()
        guard let scriptPath else {
            let msg = "Could not locate ableton_version_export.py"
            lastResult = msg
            isRunningExport = false
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
            isRunningExport = false
            AccountDiagnostics.record(msg)
            sendNotification(title: "goodvibrations HQ", body: msg)
            return
        }

        // Wait off the main actor so we don't block the UI.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isUntitled = process.terminationStatus == 2 || output.localizedCaseInsensitiveContains("untitled")
        let success = process.terminationStatus == 0 && !isUntitled
        let summary: String
        if isUntitled {
            summary = "⚠️ Track is Untitled — please save with a name first"
        } else if success {
            summary = "Export triggered successfully"
        } else {
            summary = "Export script finished with errors"
        }
        lastResult = summary
        isRunningExport = false
        AccountDiagnostics.record("\(summary): \(output.prefix(200))")
        if !isUntitled {
            sendNotification(title: "goodvibrations HQ", body: summary)
        }
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
