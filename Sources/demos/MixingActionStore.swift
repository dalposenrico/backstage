import AppKit
import Combine
import Foundation

struct MixingActionItem: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let systemIcon: String
    let scriptOrMacroName: String
    let isKeyboardMaestro: Bool

    init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String,
        systemIcon: String = "slider.vertical.3",
        scriptOrMacroName: String,
        isKeyboardMaestro: Bool = true
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemIcon = systemIcon
        self.scriptOrMacroName = scriptOrMacroName
        self.isKeyboardMaestro = isKeyboardMaestro
    }
}

@MainActor
final class MixingActionStore: ObservableObject {
    @Published private(set) var customActions: [MixingActionItem] = []
    @Published var lastActionResult: String? = nil
    @Published var isExecutingAction: Bool = false

    static let shared = MixingActionStore()

    init() {
        // Default recommended mixing macros
        customActions = [
            MixingActionItem(
                id: "gain_staging_macro",
                title: "Run Gain Staging Macro",
                subtitle: "Automate input trims across tracks in Live",
                systemIcon: "waveform.path.badge.plus",
                scriptOrMacroName: "Ableton Gain Staging",
                isKeyboardMaestro: true
            ),
            MixingActionItem(
                id: "busses_prep_macro",
                title: "Mix Bus Routing Prep",
                subtitle: "Organize stem groups and sub-mix routing",
                systemIcon: "folder.badge.gearshape",
                scriptOrMacroName: "Ableton Mix Bus Prep",
                isKeyboardMaestro: true
            ),
            MixingActionItem(
                id: "bypass_latency_macro",
                title: "Toggle Heavy FX Bypass",
                subtitle: "Bypass high-latency plugins for tracking or auditioning",
                systemIcon: "bolt.horizontal.circle",
                scriptOrMacroName: "Ableton Toggle Heavy FX",
                isKeyboardMaestro: true
            )
        ]
    }

    /// Brings Ableton Live forward to focus on the project and optionally focuses the track.
    func jumpToAbleton(project: Project? = nil, trackName: String? = nil) {
        let runningApps = NSWorkspace.shared.runningApplications
        let abletonApp = runningApps.first { app in
            app.bundleIdentifier?.lowercased().hasPrefix("com.ableton.live") == true
                || app.localizedName?.localizedCaseInsensitiveContains("Ableton Live") == true
        }

        guard let abletonApp else {
            // Ableton not currently open, open project file directly if available
            if let version = project?.versions.first {
                NSWorkspace.shared.open(version.url)
                lastActionResult = "Opening \(project?.name ?? "project") in Ableton Live..."
            }
            return
        }

        // Activate Ableton Live
        abletonApp.activate(options: .activateAllWindows)

        // If track name is provided, copy to clipboard so producer can quick-search or paste
        if let trackName, !trackName.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(trackName, forType: .string)
            lastActionResult = "Focused Ableton Live · Track '\(trackName)' copied to clipboard"
        } else {
            lastActionResult = "Focused Ableton Live"
        }
    }

    /// Executes a mixing macro or shell script.
    func executeAction(_ action: MixingActionItem) {
        isExecutingAction = true
        lastActionResult = "Running \(action.title)..."

        if action.isKeyboardMaestro {
            executeKeyboardMaestro(named: action.scriptOrMacroName)
        } else {
            executeShellScript(at: action.scriptOrMacroName)
        }
    }

    private func executeKeyboardMaestro(named macroName: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.stairways.keyboardmaestro.editor") else {
            self.lastActionResult = "Keyboard Maestro is not installed"
            self.isExecutingAction = false
            return
        }

        let commandURL = appURL.appendingPathComponent("Contents/MacOS/keyboardmaestro")
        let process = Process()
        process.executableURL = commandURL
        process.arguments = [macroName]

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try process.run()
                process.waitUntilExit()
                DispatchQueue.main.async {
                    self.isExecutingAction = false
                    self.lastActionResult = "Triggered '\(macroName)' via Keyboard Maestro"
                }
            } catch {
                DispatchQueue.main.async {
                    self.isExecutingAction = false
                    self.lastActionResult = "Failed to run macro: \(error.localizedDescription)"
                }
            }
        }
    }

    private func executeShellScript(at path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", path]

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try process.run()
                process.waitUntilExit()
                DispatchQueue.main.async {
                    self.isExecutingAction = false
                    self.lastActionResult = "Script executed successfully"
                }
            } catch {
                DispatchQueue.main.async {
                    self.isExecutingAction = false
                    self.lastActionResult = "Script failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
