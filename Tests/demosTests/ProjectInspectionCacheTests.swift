import XCTest
@testable import demos

final class ProjectInspectionCacheTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gvhq-inspection-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeFile(named name: String, contents: String = "<Ableton/>") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func setModificationDate(_ date: Date, on url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    func testFingerprintChangesWhenAProjectFileIsSaved() throws {
        let project = try makeFile(named: "Song.als")
        let before = try XCTUnwrap(AbletonProjectInspector.fingerprint(projectFiles: [project], backupFiles: []))
        try setModificationDate(Date(timeIntervalSince1970: 1_700_000_000), on: project)
        let after = try XCTUnwrap(AbletonProjectInspector.fingerprint(projectFiles: [project], backupFiles: []))
        XCTAssertNotEqual(before, after)
    }

    func testFingerprintChangesWhenABackupIsAdded() throws {
        let project = try makeFile(named: "Song.als")
        let backup = try makeFile(named: "Backup/Song [2026-01-01].als")
        let withoutBackup = try XCTUnwrap(
            AbletonProjectInspector.fingerprint(projectFiles: [project], backupFiles: [])
        )
        let withBackup = try XCTUnwrap(
            AbletonProjectInspector.fingerprint(projectFiles: [project], backupFiles: [backup])
        )
        XCTAssertNotEqual(withoutBackup, withBackup)
    }

    func testFingerprintIsStableForUnchangedFiles() throws {
        let project = try makeFile(named: "Song.als")
        let first = AbletonProjectInspector.fingerprint(projectFiles: [project], backupFiles: [])
        let second = AbletonProjectInspector.fingerprint(projectFiles: [project], backupFiles: [])
        XCTAssertEqual(first, second)
    }

    func testCacheReturnsStoredInspectionAndSurvivesReload() throws {
        let fileURL = directory.appendingPathComponent("cache.json")
        let inspection = CachedInspection(
            bpm: 124,
            plugins: ["Serum"],
            activity: ProjectActivity(
                backupCount: 3,
                sessionCount: 2,
                estimatedWorkTime: 5_400,
                firstSave: Date(timeIntervalSince1970: 1_700_000_000),
                latestSave: Date(timeIntervalSince1970: 1_700_050_000)
            )
        )

        let cache = ProjectInspectionCache(fileURL: fileURL)
        cache.beginScan()
        XCTAssertNil(cache.cached(for: "key"))
        cache.store(inspection, for: "key")
        cache.persistIfNeeded()

        let reloaded = ProjectInspectionCache(fileURL: fileURL)
        XCTAssertEqual(reloaded.cached(for: "key"), inspection)
    }

    func testPersistDropsEntriesFromProjectsThatAreGone() throws {
        let fileURL = directory.appendingPathComponent("cache.json")
        let stale = CachedInspection(bpm: nil, plugins: [], activity: ProjectActivity())
        let fresh = CachedInspection(bpm: 90, plugins: [], activity: ProjectActivity(backupCount: 1))

        let cache = ProjectInspectionCache(fileURL: fileURL)
        cache.beginScan()
        cache.store(stale, for: "removed-project")
        cache.persistIfNeeded()

        cache.beginScan()
        cache.store(fresh, for: "kept-project")
        cache.persistIfNeeded()

        let reloaded = ProjectInspectionCache(fileURL: fileURL)
        XCTAssertNil(reloaded.cached(for: "removed-project"))
        XCTAssertEqual(reloaded.cached(for: "kept-project"), fresh)
    }

    func testPersistWritesNothingWhenTheCacheIsUnchanged() throws {
        let fileURL = directory.appendingPathComponent("cache.json")
        let inspection = CachedInspection(bpm: 100, plugins: [], activity: ProjectActivity())

        let cache = ProjectInspectionCache(fileURL: fileURL)
        cache.beginScan()
        cache.store(inspection, for: "key")
        cache.persistIfNeeded()
        let written = try XCTUnwrap(try? Data(contentsOf: fileURL).count)

        cache.beginScan()
        cache.store(inspection, for: "key")
        cache.persistIfNeeded()
        XCTAssertEqual(try Data(contentsOf: fileURL).count, written)
    }
}
