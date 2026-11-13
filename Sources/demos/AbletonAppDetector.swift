import AppKit
import Foundation

/// Represents an installed or detected Ableton Live application on the system.
public struct AbletonAppInfo: Identifiable, Hashable, Equatable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let bundleURL: URL
    public let bundleIdentifier: String?
    public let version: String?
    public let isBeta: Bool

    public var displayName: String {
        var base = name
        if base.hasSuffix(".app") {
            base = String(base.dropLast(4))
        }
        if let cleanVersion = cleanVersion, !cleanVersion.isEmpty, !base.localizedCaseInsensitiveContains(cleanVersion) {
            return "\(base) (\(cleanVersion))"
        }
        return base
    }

    public var pickerLabel: String {
        if isBeta && !name.localizedCaseInsensitiveContains("Beta") {
            return "\(displayName) [Beta]"
        }
        return displayName
    }

    public var cleanVersion: String? {
        guard let version = version?.trimmingCharacters(in: .whitespacesAndNewlines), !version.isEmpty else {
            return nil
        }
        // Extract version up to space or parenthesis, e.g. "12.4.16 (2026-10-30)" -> "12.4.16"
        let parts = version.components(separatedBy: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "()")))
        return parts.first { !$0.isEmpty } ?? version
    }

    /// Major version prefix for matching preferences directory, e.g. "Live 12" or "Live 13"
    public var majorVersionPrefix: String? {
        if let clean = cleanVersion {
            let digits = clean.prefix { $0.isNumber }
            if !digits.isEmpty {
                return "Live \(digits)"
            }
        }
        // Fallback to name inspection, e.g. "Ableton Live 13 Beta" -> "Live 13"
        for num in (10...20).reversed() {
            if name.localizedCaseInsensitiveContains("Live \(num)") || name.localizedCaseInsensitiveContains("Live\(num)") {
                return "Live \(num)"
            }
        }
        return nil
    }
}

/// Discovers installed Ableton Live application bundles, manages the user's preferred Live app,
/// and handles opening project files directly in the selected application.
public enum AbletonAppDetector {
    public static let defaultsKey = "selectedAbletonAppPath"

    /// Returns the standardized URL of the user's explicitly selected Ableton Live app,
    /// or `nil` if set to Auto-detect / System Default or if the file no longer exists.
    public static func selectedAppURL() -> URL? {
        guard let path = selectedAppPath() else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Returns the path string of the user's selected Ableton Live app, or nil if unset/invalid.
    public static func selectedAppPath() -> String? {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty else {
            return nil
        }
        guard FileManager.default.fileExists(atPath: raw) else {
            return nil
        }
        return raw
    }

    /// Sets or clears the user's selected Ableton Live app path.
    public static func setSelectedAppPath(_ path: String?) {
        if let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            UserDefaults.standard.set(path, forKey: defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }

    /// Inspects an application bundle at `url` to see if it is a valid Ableton Live application.
    public static func appInfo(for url: URL) -> AbletonAppInfo? {
        let bundleURL = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: bundleURL.path) else { return nil }

        let bundle = Bundle(url: bundleURL)
        let info = bundle?.infoDictionary

        let bundleID = bundle?.bundleIdentifier
        let displayName = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? bundleURL.deletingPathExtension().lastPathComponent

        let rawVersion = (info?["CFBundleShortVersionString"] as? String)
            ?? (info?["CFBundleVersion"] as? String)

        let executable = (info?["CFBundleExecutable"] as? String) ?? ""

        // Validate that this is indeed an Ableton Live app
        let isAbletonBundleID = bundleID?.lowercased().hasPrefix("com.ableton.live") == true
            || bundleID?.lowercased().contains("ableton") == true
        let isLiveName = displayName.localizedCaseInsensitiveContains("Live")
            || displayName.localizedCaseInsensitiveContains("Ableton")
        let isLiveExecutable = executable.localizedCaseInsensitiveCompare("Live") == .orderedSame

        guard isAbletonBundleID || (isLiveName && isLiveExecutable) || isLiveName else {
            return nil
        }

        // Detect if this is a Beta build
        let isBeta = displayName.localizedCaseInsensitiveContains("Beta")
            || bundleURL.lastPathComponent.localizedCaseInsensitiveContains("Beta")
            || (rawVersion?.localizedCaseInsensitiveContains("b") == true)

        return AbletonAppInfo(
            name: displayName,
            path: bundleURL.path,
            bundleURL: bundleURL,
            bundleIdentifier: bundleID,
            version: rawVersion,
            isBeta: isBeta
        )
    }

    /// Discovers all available Ableton Live applications installed on this Mac.
    public static func discoverInstalledApps() -> [AbletonAppInfo] {
        var foundPaths = Set<String>()
        var results: [AbletonAppInfo] = []

        func checkURL(_ url: URL) {
            let stdPath = url.standardizedFileURL.path
            guard !foundPaths.contains(stdPath) else { return }
            if let info = appInfo(for: url) {
                foundPaths.insert(stdPath)
                results.append(info)
            }
        }

        // 1. Check user-selected app if configured
        if let currentPath = selectedAppPath() {
            checkURL(URL(fileURLWithPath: currentPath))
        }

        // 2. Scan standard Application folders
        let searchDirectories: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]

        for dir in searchDirectories {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for item in contents where item.pathExtension.lowercased() == "app" {
                let name = item.lastPathComponent
                if name.localizedCaseInsensitiveContains("Live") || name.localizedCaseInsensitiveContains("Ableton") {
                    checkURL(item)
                }
            }
        }

        // 3. Check currently running apps
        for app in NSWorkspace.shared.runningApplications {
            if let bundleURL = app.bundleURL {
                let bundleID = app.bundleIdentifier?.lowercased() ?? ""
                let name = app.localizedName ?? ""
                if bundleID.hasPrefix("com.ableton.live") || name.localizedCaseInsensitiveContains("Live") {
                    checkURL(bundleURL)
                }
            }
        }

        // 4. Fast Spotlight fallback via mdfind
        let queryResults = runSpotlightQuery("kMDItemCFBundleIdentifier == 'com.ableton.live*'")
        for path in queryResults {
            checkURL(URL(fileURLWithPath: path))
        }

        // Sort results: Beta / higher versions first, then alphabetically
        return results.sorted { a, b in
            if a.isBeta != b.isBeta {
                // If versions are similar, sort logically; otherwise sort by name
                return a.name.localizedStandardCompare(b.name) == .orderedDescending
            }
            return a.name.localizedStandardCompare(b.name) == .orderedDescending
        }
    }

    /// Opens an Ableton project file (.als) using the selected Live app, or the system default.
    public static func openALS(at alsURL: URL, preferredAppURL: URL? = selectedAppURL(), completion: ((Bool) -> Void)? = nil) {
        if let appURL = preferredAppURL, FileManager.default.fileExists(atPath: appURL.path) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([alsURL], withApplicationAt: appURL, configuration: config) { _, error in
                if let error = error {
                    AccountDiagnostics.record("Failed to open ALS with preferred app \(appURL.path): \(error.localizedDescription), falling back to default")
                    DispatchQueue.main.async {
                        NSWorkspace.shared.open(alsURL)
                        completion?(false)
                    }
                } else {
                    completion?(true)
                }
            }
        } else {
            NSWorkspace.shared.open(alsURL)
            completion?(true)
        }
    }

    private static func runSpotlightQuery(_ query: String) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = [query]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let text = String(data: data, encoding: .utf8) else {
                return []
            }
            return text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.hasSuffix(".app") }
        } catch {
            return []
        }
    }
}
