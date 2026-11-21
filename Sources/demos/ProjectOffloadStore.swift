import Foundation
import AppKit

// MARK: - Size Breakdown
struct OffloadSizeBreakdown: Sendable {
    let totalBytes: Int64
    let samplesBytes: Int64
    let backupBytes: Int64
    let alsBytes: Int64
    let exportsBytes: Int64
    let otherBytes: Int64

    var formattedTotal: String { ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file) }
    var formattedSamples: String { ByteCountFormatter.string(fromByteCount: samplesBytes, countStyle: .file) }
    var formattedBackups: String { ByteCountFormatter.string(fromByteCount: backupBytes, countStyle: .file) }
    var formattedAls: String { ByteCountFormatter.string(fromByteCount: alsBytes, countStyle: .file) }
    var formattedExports: String { ByteCountFormatter.string(fromByteCount: exportsBytes, countStyle: .file) }

    var estimatedSavings: Int64 {
        // Savings = total - exports
        max(0, totalBytes - exportsBytes)
    }

    var formattedEstimatedSavings: String {
        ByteCountFormatter.string(fromByteCount: estimatedSavings, countStyle: .file)
    }
}

// MARK: - Export Readiness
enum ExportReadiness: Equatable {
    case ready(primaryTrack: Track, isOutdated: Bool)
    case missing
}

// MARK: - Offloaded Metadata Snapshot
struct OffloadMetadataSnapshot: Codable, Hashable {
    let bpm: Double?
    let key: String?
    let timeSignature: String?
    let plugins: [String]
    let liveVersion: String?
    let tracksCount: Int?
    let samplesCount: Int?
    let versionNames: [String]
    let tags: [String]
    let notes: String?
    let activityBackupCount: Int
    let activitySessionCount: Int
    let activityEstimatedWorkTime: TimeInterval
    let originalLatestModification: Date?
}

// MARK: - Offloaded Project Record
struct OffloadedProjectRecord: Codable, Identifiable, Hashable {
    var id: String { originalFolderPath }
    let originalFolderPath: String
    let projectName: String
    let archivePath: String
    let cachedExportPath: String?
    let cachedExportRelativeName: String?
    let offloadedDate: Date
    let freedBytes: Int64
    let metadataSnapshot: OffloadMetadataSnapshot

    var archiveURL: URL { URL(fileURLWithPath: archivePath) }
    var originalFolderURL: URL { URL(fileURLWithPath: originalFolderPath) }
    var cachedExportURL: URL? { cachedExportPath.map { URL(fileURLWithPath: $0) } }

    var formattedFreedBytes: String {
        ByteCountFormatter.string(fromByteCount: freedBytes, countStyle: .file)
    }
}

// MARK: - Project Offload Store
enum OffloadOperationState: Equatable {
    case offloading
    case restoring
}

@MainActor
final class ProjectOffloadStore: ObservableObject {
    static let shared = ProjectOffloadStore()

    @Published private(set) var offloadedProjects: [String: OffloadedProjectRecord] = [:]
    @Published private(set) var activeOperations: [String: OffloadOperationState] = [:]
    @Published private(set) var localProjectSizes: [String: Int64] = [:]
    @Published var missingExportNoticeProject: Project?

    private var calculatingSizes = Set<String>()
    private let storeFileURL: URL
    private let offloadVaultBaseURL: URL
    nonisolated static let markerFileName = "_goodvibrations_offloaded.json"

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let backstageDir = appSupport.appendingPathComponent("Backstage", isDirectory: true)
        try? FileManager.default.createDirectory(at: backstageDir, withIntermediateDirectories: true)
        storeFileURL = backstageDir.appendingPathComponent("project-offloads.json")
        offloadVaultBaseURL = backstageDir.appendingPathComponent("OffloadVault", isDirectory: true)
        try? FileManager.default.createDirectory(at: offloadVaultBaseURL, withIntermediateDirectories: true)

        loadPersistedRecords()
    }

    // MARK: - Persistence
    private func loadPersistedRecords() {
        guard let data = try? Data(contentsOf: storeFileURL),
              let decoded = try? JSONDecoder().decode([String: OffloadedProjectRecord].self, from: data) else {
            return
        }
        offloadedProjects = decoded
    }

    private func savePersistedRecords() {
        guard let data = try? JSONEncoder().encode(offloadedProjects) else { return }
        try? data.write(to: storeFileURL, options: .atomic)
    }

    func isOffloaded(folderURL: URL) -> Bool {
        let path = folderURL.standardizedFileURL.path
        if offloadedProjects[path] != nil { return true }
        let marker = folderURL.appendingPathComponent(Self.markerFileName)
        return FileManager.default.fileExists(atPath: marker.path)
    }

    func record(for folderURL: URL) -> OffloadedProjectRecord? {
        let path = folderURL.standardizedFileURL.path
        if let existing = offloadedProjects[path] {
            return existing
        }
        // Fallback: check on-disk marker
        return Self.readMarker(in: folderURL)
    }

    nonisolated static func readMarker(in folderURL: URL) -> OffloadedProjectRecord? {
        let marker = folderURL.appendingPathComponent(markerFileName)
        guard let data = try? Data(contentsOf: marker),
              let record = try? JSONDecoder().decode(OffloadedProjectRecord.self, from: data) else {
            return nil
        }
        return record
    }

    // MARK: - Export Readiness Check
    func checkExportReadiness(for project: Project) -> ExportReadiness {
        guard let primary = project.primaryTrack else {
            return .missing
        }
        let exportDate = primary.modificationDate ?? .distantPast
        let newestAlsDate = project.newestAbletonVersion?.modificationDate ?? .distantPast
        let isOutdated = newestAlsDate > exportDate && newestAlsDate != .distantPast
        return .ready(primaryTrack: primary, isOutdated: isOutdated)
    }

    // MARK: - Size Caching & Asynchronous Lookups
    func requestSize(for folderURL: URL) {
        let path = folderURL.standardizedFileURL.path
        guard localProjectSizes[path] == nil, !calculatingSizes.contains(path) else { return }
        calculatingSizes.insert(path)

        Task {
            let breakdown = await calculateSize(for: folderURL)
            self.localProjectSizes[path] = breakdown.totalBytes
            self.calculatingSizes.remove(path)
        }
    }

    func cachedFormattedSize(for folderURL: URL) -> String? {
        let path = folderURL.standardizedFileURL.path
        guard let bytes = localProjectSizes[path], bytes > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func setCachedSize(_ bytes: Int64, for folderURL: URL) {
        localProjectSizes[folderURL.standardizedFileURL.path] = bytes
    }

    // MARK: - Non-blocking Background Queue Operations
    func queueOffload(project: Project) {
        let path = project.folderURL.standardizedFileURL.path
        guard activeOperations[path] == nil else { return }

        // Pre-flight check: ensure project has an audio export
        if checkExportReadiness(for: project) == .missing {
            missingExportNoticeProject = project
            return
        }

        activeOperations[path] = .offloading

        Task {
            do {
                _ = try await offloadProject(project: project)
                await AppStore.shared?.refreshProject(project)
            } catch {
                print("Background offload failed for \(project.name): \(error.localizedDescription)")
            }
            self.activeOperations.removeValue(forKey: path)
        }
    }

    func queueRestore(project: Project) {
        let path = project.folderURL.standardizedFileURL.path
        guard activeOperations[path] == nil else { return }

        activeOperations[path] = .restoring

        Task {
            do {
                try await restoreProject(project: project)
                await AppStore.shared?.refreshProject(project)
            } catch {
                print("Background restore failed for \(project.name): \(error.localizedDescription)")
            }
            self.activeOperations.removeValue(forKey: path)
        }
    }

    // MARK: - Automatic Inactive Project Offloading
    func eligibleProjectsForAutoOffload(in projects: [Project], threshold: AutoOffloadAge) -> [Project] {
        let cutoffDate = Date().addingTimeInterval(-threshold.timeInterval)
        return projects.filter { project in
            !project.isOffloaded &&
            project.hasExports &&
            project.latestModification != .distantPast &&
            project.latestModification < cutoffDate &&
            activeOperations[project.folderURL.standardizedFileURL.path] == nil
        }
    }

    @discardableResult
    func performAutoOffload(projects: [Project], threshold: AutoOffloadAge) -> Int {
        let eligible = eligibleProjectsForAutoOffload(in: projects, threshold: threshold)
        for project in eligible {
            queueOffload(project: project)
        }
        return eligible.count
    }

    func estimatedReclaimableBytes(for projects: [Project]) -> Int64 {
        projects.reduce(0) { total, project in
            let path = project.folderURL.standardizedFileURL.path
            if let cached = localProjectSizes[path] {
                return total + cached
            }
            requestSize(for: project.folderURL)
            return total
        }
    }

    func formattedReclaimableBytes(for projects: [Project]) -> String? {
        let bytes = estimatedReclaimableBytes(for: projects)
        guard bytes > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Size Calculation
    nonisolated func calculateSize(for folderURL: URL) async -> OffloadSizeBreakdown {
        await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            var totalBytes: Int64 = 0
            var samplesBytes: Int64 = 0
            var backupBytes: Int64 = 0
            var alsBytes: Int64 = 0
            var exportsBytes: Int64 = 0
            var otherBytes: Int64 = 0

            guard let enumerator = fm.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return OffloadSizeBreakdown(totalBytes: 0, samplesBytes: 0, backupBytes: 0, alsBytes: 0, exportsBytes: 0, otherBytes: 0)
            }

            let folderPath = folderURL.standardizedFileURL.path

            while let fileURL = enumerator.nextObject() as? URL {
                guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                      values.isDirectory == false,
                      let size = values.fileSize else { continue }

                let bytes = Int64(size)
                totalBytes += bytes

                let relative = String(fileURL.standardizedFileURL.path.dropFirst(folderPath.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let components = relative.split(separator: "/")
                let topFolder = components.first?.lowercased() ?? ""
                let ext = fileURL.pathExtension.lowercased()

                if topFolder == "samples" {
                    samplesBytes += bytes
                } else if topFolder == "backup" {
                    backupBytes += bytes
                } else if ext == "als" {
                    alsBytes += bytes
                } else if ProjectScanner.audioExtensions.contains(ext) {
                    exportsBytes += bytes
                } else {
                    otherBytes += bytes
                }
            }

            return OffloadSizeBreakdown(
                totalBytes: totalBytes,
                samplesBytes: samplesBytes,
                backupBytes: backupBytes,
                alsBytes: alsBytes,
                exportsBytes: exportsBytes,
                otherBytes: otherBytes
            )
        }.value
    }

    // MARK: - Offload Operation
    func offloadProject(
        project: Project,
        customArchiveDestination: URL? = nil,
        keepAudioExport: Bool = true
    ) async throws -> OffloadedProjectRecord {
        let folder = project.folderURL.standardizedFileURL
        let fm = FileManager.default

        // Preserve original modification dates so offloading never alters the project timeline
        let originalLatestModification = project.latestModification
        let originalFolderModDate = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

        // 1. Calculate size breakdown before modifying
        let sizeBreakdown = await calculateSize(for: folder)

        // 2. Identify primary track / exports to preserve locally
        let primaryTrack = project.primaryTrack
        let vaultFolder = offloadVaultBaseURL.appendingPathComponent(folder.lastPathComponent, isDirectory: true)
        try? fm.createDirectory(at: vaultFolder, withIntermediateDirectories: true)

        var cachedExportPath: String? = nil
        var cachedExportRelativeName: String? = nil

        if let primaryTrack {
            let dest = vaultFolder.appendingPathComponent(primaryTrack.url.lastPathComponent)
            try? fm.removeItem(at: dest)
            try? fm.copyItem(at: primaryTrack.url, to: dest)
            cachedExportPath = dest.path
            cachedExportRelativeName = primaryTrack.url.lastPathComponent
        }

        // 3. Resolve archive destination
        let archiveFolder = customArchiveDestination?.deletingLastPathComponent()
            ?? DropboxManager.shared.archiveDirectoryURL()
        try fm.createDirectory(at: archiveFolder, withIntermediateDirectories: true)

        let safeProjectName = project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? folder.lastPathComponent
            : project.name
        let archiveURL = customArchiveDestination ?? archiveFolder.appendingPathComponent("\(safeProjectName).zip")

        // 4. Archive project using ditto
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = [
                "-c", "-k",
                "--sequesterRsrc",
                "--keepParent",
                folder.path,
                archiveURL.path
            ]
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                throw NSError(
                    domain: "ProjectOffloadStore",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "Failed to compress project into archive (code \(process.terminationStatus))."]
                )
            }
        }.value

        // Verify archive was created
        guard fm.fileExists(atPath: archiveURL.path) else {
            throw NSError(
                domain: "ProjectOffloadStore",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Archive file was not created."]
            )
        }

        // 5. Build metadata snapshot
        let snapshot = OffloadMetadataSnapshot(
            bpm: project.bpm,
            key: project.key,
            timeSignature: project.timeSignature,
            plugins: project.plugins,
            liveVersion: project.liveVersion,
            tracksCount: project.tracksCount,
            samplesCount: project.samplesCount,
            versionNames: project.versions.map(\.displayName),
            tags: project.tags,
            notes: ProjectNotesStore().note(for: project),
            activityBackupCount: project.activity.backupCount,
            activitySessionCount: project.activity.sessionCount,
            activityEstimatedWorkTime: project.activity.estimatedWorkTime,
            originalLatestModification: originalLatestModification
        )

        let freedBytes = sizeBreakdown.estimatedSavings
        let record = OffloadedProjectRecord(
            originalFolderPath: folder.path,
            projectName: project.name,
            archivePath: archiveURL.path,
            cachedExportPath: cachedExportPath,
            cachedExportRelativeName: cachedExportRelativeName,
            offloadedDate: Date(),
            freedBytes: freedBytes,
            metadataSnapshot: snapshot
        )

        // 6. Delete heavy items inside project folder, preserving the export
        let contents = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for item in contents {
            let name = item.lastPathComponent.lowercased()
            if name == "samples" || name == "backup" || name == "ableton project info" {
                try? fm.removeItem(at: item)
            } else if item.pathExtension.lowercased() == "als" {
                try? fm.removeItem(at: item)
            }
        }

        // Write marker file in the project folder
        let markerURL = folder.appendingPathComponent(Self.markerFileName)
        if let markerData = try? JSONEncoder().encode(record) {
            try? markerData.write(to: markerURL, options: .atomic)
        }

        // Restore original modification date on disk so Finder and scanners don't think it was edited today
        if let originalFolderModDate {
            try? fm.setAttributes([.modificationDate: originalFolderModDate], ofItemAtPath: folder.path)
        }

        // 7. Save in store
        offloadedProjects[folder.path] = record
        savePersistedRecords()

        return record
    }

    // MARK: - Restore Operation
    func restoreProject(project: Project) async throws {
        let folder = project.folderURL.standardizedFileURL
        guard let record = self.record(for: folder) else {
            throw NSError(
                domain: "ProjectOffloadStore",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No offload record found for project at \(folder.path)."]
            )
        }

        let archiveURL = record.archiveURL
        let fm = FileManager.default

        guard fm.fileExists(atPath: archiveURL.path) else {
            throw NSError(
                domain: "ProjectOffloadStore",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Cloud archive not found at: \(archiveURL.path). Please verify Dropbox has synced this file."]
            )
        }

        // Extract using ditto into the parent directory
        let parentDir = folder.deletingLastPathComponent()

        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = [
                "-x", "-k",
                archiveURL.path,
                parentDir.path
            ]
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                throw NSError(
                    domain: "ProjectOffloadStore",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "Failed to extract project archive (code \(process.terminationStatus))."]
                )
            }
        }.value

        // Remove the marker file
        let markerURL = folder.appendingPathComponent(Self.markerFileName)
        try? fm.removeItem(at: markerURL)

        // Restore original modification date on disk if known
        if let originalModDate = record.metadataSnapshot.originalLatestModification {
            try? fm.setAttributes([.modificationDate: originalModDate], ofItemAtPath: folder.path)
        }

        // Remove from memory and save
        offloadedProjects.removeValue(forKey: folder.path)
        savePersistedRecords()
    }
}
