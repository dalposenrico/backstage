import AppKit
import Combine
import Foundation

enum ToolLauncherKind: String, Codable {
    case file
    case keyboardMaestroMacro
}

struct ToolLauncher: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    let path: String
    let dateAdded: Date
    let kind: ToolLauncherKind?
    let activateBundleIdentifier: String? // Legacy field; no longer used for launching.

    var url: URL { URL(fileURLWithPath: path) }
    var isKeyboardMaestroMacro: Bool { kind == .keyboardMaestroMacro }
}

@MainActor
final class ToolLauncherStore: ObservableObject {
    @Published private(set) var tools: [ToolLauncher] = []

    private static let fileURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support.appendingPathComponent("Backstage", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("tools.json")
    }()

    init() { load() }

    func addTools() {
        let panel = NSOpenPanel()
        panel.title = "Add Tools to goodvibrations HQ"
        panel.message = "Choose apps, files, scripts, Keyboard Maestro files, or folders."
        panel.prompt = "Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true

        guard panel.runModal() == .OK else { return }
        let existingPaths = Set(tools.map(\.path))
        let additions = panel.urls
            .filter { !existingPaths.contains($0.path) }
            .map {
                ToolLauncher(id: UUID(), name: $0.deletingPathExtension().lastPathComponent,
                             path: $0.path, dateAdded: .now, kind: .file,
                             activateBundleIdentifier: nil)
            }
        tools.append(contentsOf: additions)
        save()
    }

    func addKeyboardMaestroMacro(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let uid = resolveKeyboardMaestroMacroUID(named: name)
        tools.append(ToolLauncher(id: UUID(), name: name, path: uid ?? name, dateAdded: .now,
                                  kind: .keyboardMaestroMacro,
                                  activateBundleIdentifier: nil))
        save()
    }

    func launch(_ tool: ToolLauncher) {
        if tool.isKeyboardMaestroMacro {
            launchKeyboardMaestroMacro(tool)
        } else {
            NSWorkspace.shared.open(tool.url)
        }
    }

    func launchAbletonCrashAnalyzer() {
        let bundledApp = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Applications/Ableton Crash Analyzer.app")
        guard FileManager.default.fileExists(atPath: bundledApp.path) else {
            print("Ableton Crash Analyzer is missing from the app bundle")
            return
        }
        NSWorkspace.shared.openApplication(at: bundledApp, configuration: .init())
    }

    private func launchKeyboardMaestroMacro(_ tool: ToolLauncher) {
        // Dismiss the transient panel, then let Keyboard Maestro and the macro manage focus.
        NSApp.keyWindow?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.runKeyboardMaestroMacro(tool.path)
        }
    }

    private func runKeyboardMaestroMacro(_ identifier: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.stairways.keyboardmaestro.editor") else {
            print("Keyboard Maestro macro failed: Keyboard Maestro is not installed")
            return
        }
        let commandURL = appURL.appendingPathComponent("Contents/MacOS/keyboardmaestro")
        let process = Process()
        process.executableURL = commandURL
        process.arguments = ["--async", identifier]
        do {
            try process.run()
        } catch {
            print("Keyboard Maestro macro failed: \(error.localizedDescription)")
        }
    }

    func reveal(_ tool: ToolLauncher) {
        NSWorkspace.shared.activateFileViewerSelecting([tool.url])
    }

    func remove(_ tool: ToolLauncher) {
        tools.removeAll { $0.id == tool.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode([ToolLauncher].self, from: data) else { return }
        tools = decoded.map { tool in
            guard tool.isKeyboardMaestroMacro else { return tool }
            let uid = resolveKeyboardMaestroMacroUID(named: tool.name)
            return ToolLauncher(id: tool.id, name: tool.name, path: uid ?? tool.path,
                                dateAdded: tool.dateAdded, kind: tool.kind,
                                activateBundleIdentifier: nil)
        }
        if tools != decoded { save() }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tools) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    private func resolveKeyboardMaestroMacroUID(named name: String) -> String? {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = support.appendingPathComponent("Keyboard Maestro/Keyboard Maestro Macros.plist")
        guard let data = try? Data(contentsOf: url),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let groups = root["MacroGroups"] as? [[String: Any]] else { return nil }

        for group in groups {
            guard let macros = group["Macros"] as? [[String: Any]],
                  let macro = macros.first(where: { ($0["Name"] as? String) == name }) else { continue }
            return macro["UID"] as? String
        }
        return nil
    }
}
