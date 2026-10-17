import Foundation

struct CrashReport: Identifiable, Hashable {
    let url: URL
    let modifiedAt: Date
    var id: String { url.path }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

struct CrashAnalysis {
    let pluginName: String
    let developer: String?
    let confidence: String
    let exception: String
    let crashFile: String
    let evidence: [String]
    let recommendation: String
}

enum CrashAnalyzerError: LocalizedError {
    case invalidArchive, missingCrashLog, unreadableCrashLog
    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "This file is not a readable ZIP archive."
        case .missingCrashLog: return "No macOS crash log was found inside this report."
        case .unreadableCrashLog: return "The crash log format could not be read."
        }
    }
}

enum CrashAnalyzer {
    static let reportsFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Ableton/Live Reports")

    static func reports() -> [CrashReport] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: reportsFolder,
                                                                       includingPropertiesForKeys: Array(keys)) else { return [] }
        return urls.filter { $0.pathExtension.lowercased() == "zip" }
            .map {
                let values = try? $0.resourceValues(forKeys: keys)
                return CrashReport(url: $0, modifiedAt: values?.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    static func analyze(_ url: URL) throws -> CrashAnalysis {
        let entries = try runUnzip(arguments: ["-Z1", url.path])
            .split(separator: "\n").map(String.init)
        guard !entries.isEmpty else { throw CrashAnalyzerError.invalidArchive }
        guard let crashEntry = entries.filter({ $0.hasPrefix("Crash/") && $0.hasSuffix(".ips") }).sorted().last
        else { throw CrashAnalyzerError.missingCrashLog }
        let raw = try runUnzipData(arguments: ["-p", url.path, crashEntry])
        guard let dictionary = parseIPSDictionary(raw) else { throw CrashAnalyzerError.unreadableCrashLog }

        let threads = dictionary["threads"] as? [[String: Any]] ?? []
        let images = dictionary["usedImages"] as? [[String: Any]] ?? []
        let faultIndex = dictionary["faultingThread"] as? Int ?? -1
        let frames = threads.indices.contains(faultIndex) ? (threads[faultIndex]["frames"] as? [[String: Any]] ?? []) : []
        let exceptionInfo = dictionary["exception"] as? [String: Any]
        let exception = [exceptionInfo?["type"] as? String, exceptionInfo?["signal"] as? String]
            .compactMap { $0 }.joined(separator: " · ")

        var candidates: [(path: String, name: String, symbol: String)] = []
        for frame in frames.prefix(25) {
            guard let imageIndex = frame["imageIndex"] as? Int, images.indices.contains(imageIndex) else { continue }
            let image = images[imageIndex]
            let path = image["path"] as? String ?? ""
            guard isPluginPath(path) else { continue }
            candidates.append((path, pluginName(from: path), frame["symbol"] as? String ?? "Unknown function"))
        }

        guard let winner = Dictionary(grouping: candidates, by: \.name).max(by: { $0.value.count < $1.value.count }) else {
            return CrashAnalysis(pluginName: "No plug-in identified", developer: nil, confidence: "Low",
                                 exception: exception.isEmpty ? "Unknown exception" : exception,
                                 crashFile: crashEntry, evidence: ["The faulting thread does not contain a third-party plug-in frame."],
                                 recommendation: "Check Ableton, audio-interface, and system logs; this report does not justify blaming a plug-in.")
        }
        let firstIndex = candidates.firstIndex { $0.name == winner.key } ?? 99
        let confidence = winner.value.count >= 3 && firstIndex < 8 ? "High" : "Medium"
        let developer = developerName(from: winner.value[0].path)
        let evidence = Array(winner.value.prefix(5)).map { "\($0.symbol) — \($0.path)" }
        return CrashAnalysis(pluginName: winner.key, developer: developer, confidence: confidence,
                             exception: exception.isEmpty ? "Unknown exception" : exception,
                             crashFile: crashEntry, evidence: evidence,
                             recommendation: "Update or temporarily remove \(winner.key), reopen the same Live Set, and see whether the crash repeats. Keep a backup before changing the set.")
    }

    private static func isPluginPath(_ path: String) -> Bool {
        path.localizedCaseInsensitiveContains("/Audio/Plug-Ins/") ||
        path.localizedCaseInsensitiveContains(".vst3/") || path.localizedCaseInsensitiveContains(".vst/") ||
        path.localizedCaseInsensitiveContains(".component/")
    }

    private static func pluginName(from path: String) -> String {
        for component in path.split(separator: "/").map(String.init) {
            let lower = component.lowercased()
            if lower.hasSuffix(".vst3") || lower.hasSuffix(".vst") || lower.hasSuffix(".component") {
                return URL(fileURLWithPath: component).deletingPathExtension().lastPathComponent
            }
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private static func developerName(from path: String) -> String? {
        let lower = path.lowercased()
        if lower.contains("acqua") || lower.contains("acustica") { return "Acustica Audio" }
        if lower.contains("fabfilter") { return "FabFilter" }
        if lower.contains("izotope") { return "iZotope" }
        if lower.contains("plugin-alliance") { return "Plugin Alliance" }
        if lower.contains("xfer") || lower.contains("serum") { return "Xfer Records" }
        return nil
    }

    private static func parseIPSDictionary(_ data: Data) -> [String: Any]? {
        guard let newline = data.firstIndex(of: 10) else { return nil }
        let remainder = data[data.index(after: newline)...]
        guard let object = firstJSONObject(in: Data(remainder)),
              let value = try? JSONSerialization.jsonObject(with: object) as? [String: Any] else { return nil }
        return value
    }

    private static func firstJSONObject(in data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard let start = bytes.firstIndex(of: 123) else { return nil }
        var depth = 0, end: Int?
        var inString = false, escaped = false
        for index in start..<bytes.count {
            let byte = bytes[index]
            if inString {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { inString = false }
            } else if byte == 34 { inString = true }
            else if byte == 123 { depth += 1 }
            else if byte == 125 {
                depth -= 1
                if depth == 0 { end = index; break }
            }
        }
        guard let end else { return nil }
        return Data(bytes[start...end])
    }

    private static func runUnzip(arguments: [String]) throws -> String {
        String(decoding: try runUnzipData(arguments: arguments), as: UTF8.self)
    }

    private static func runUnzipData(arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CrashAnalyzerError.invalidArchive }
        return data
    }
}
