import Foundation

/// The parts of `AbletonProjectInspector.Result` that are expensive to obtain and
/// safe to remember. Reading a project's BPM and plug-ins means gunzipping a
/// multi-megabyte XML document and running several regular expressions over it;
/// an unchanged export should only ever pay that cost once.
struct CachedInspection: Codable, Equatable {
    let bpm: Double?
    let plugins: [String]
    let activity: ProjectActivity
    var key: String? = nil
    var timeSignature: String? = nil
    var liveVersion: String? = nil
    var tracksCount: Int? = nil
    var samplesCount: Int? = nil

    init(
        bpm: Double?,
        plugins: [String],
        activity: ProjectActivity,
        key: String? = nil,
        timeSignature: String? = nil,
        liveVersion: String? = nil,
        tracksCount: Int? = nil,
        samplesCount: Int? = nil
    ) {
        self.bpm = bpm
        self.plugins = plugins
        self.activity = activity
        self.key = key
        self.timeSignature = timeSignature
        self.liveVersion = liveVersion
        self.tracksCount = tracksCount
        self.samplesCount = samplesCount
    }
}

/// Remembers inspection results after the first scan of a project so relaunching
/// or rescanning an unchanged library skips the XML work entirely.
///
/// Keys are built from the `.als` files themselves (path, size, modification
/// date), so any edit in Ableton, new backup, or manual save produces a miss and
/// a fresh read. Entries that no longer match anything during a full scan are
/// dropped, which keeps the file from growing without bound.
final class ProjectInspectionCache: @unchecked Sendable {
    private struct Payload: Codable {
        var entries: [String: CachedInspection]
    }

    nonisolated static let defaultFileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("Backstage")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("inspection-cache.json")
    }()

    private let fileURL: URL
    private let lock = NSLock()
    private var entries: [String: CachedInspection] = [:]
    private var usedKeys = Set<String>()
    private var isDirty = false

    init(fileURL: URL = ProjectInspectionCache.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    /// Begins a full library scan: keys touched from here on are the ones kept.
    func beginScan() {
        lock.lock()
        usedKeys.removeAll()
        lock.unlock()
    }

    func cached(for key: String) -> CachedInspection? {
        lock.lock()
        defer { lock.unlock() }
        usedKeys.insert(key)
        return entries[key]
    }

    func store(_ inspection: CachedInspection, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        usedKeys.insert(key)
        guard entries[key] != inspection else { return }
        entries[key] = inspection
        isDirty = true
    }

    /// Writes the cache to disk only when a scan actually produced new results.
    func persistIfNeeded() {
        lock.lock()
        guard isDirty else {
            lock.unlock()
            return
        }
        if !usedKeys.isEmpty {
            entries = entries.filter { usedKeys.contains($0.key) }
        }
        let snapshot = entries
        isDirty = false
        lock.unlock()

        guard let data = try? JSONEncoder().encode(Payload(entries: snapshot)) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        entries = payload.entries
    }
}
