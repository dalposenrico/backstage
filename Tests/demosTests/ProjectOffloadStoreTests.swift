import XCTest
@testable import demos

@MainActor
final class ProjectOffloadStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    func testExportReadinessDetectsMissingAndReady() {
        let store = ProjectOffloadStore.shared
        let dummyFolder = tempDir.appendingPathComponent("Song A", isDirectory: true)

        // 1. Missing export
        let projectWithoutExport = Project(
            name: "Song A",
            folderURL: dummyFolder,
            tracks: [],
            versions: [],
            creationDate: Date(),
            tags: [],
            bpm: 124,
            plugins: [],
            activity: ProjectActivity()
        )
        XCTAssertEqual(store.checkExportReadiness(for: projectWithoutExport), .missing)

        // 2. Ready export
        let exportURL = dummyFolder.appendingPathComponent("Song A v1.mp3")
        let track = Track(url: exportURL, modificationDate: Date(), creationDate: Date(), relativeFolder: "")
        let projectWithExport = Project(
            name: "Song A",
            folderURL: dummyFolder,
            tracks: [track],
            versions: [],
            creationDate: Date(),
            tags: [],
            bpm: 124,
            plugins: [],
            activity: ProjectActivity()
        )
        XCTAssertEqual(store.checkExportReadiness(for: projectWithExport), .ready(primaryTrack: track, isOutdated: false))
    }

    func testSizeBreakdownCalculatesBytesAcrossSubfolders() async throws {
        let fm = FileManager.default
        let projectFolder = tempDir.appendingPathComponent("Deep Project", isDirectory: true)
        let samplesFolder = projectFolder.appendingPathComponent("Samples/Recorded", isDirectory: true)
        let backupFolder = projectFolder.appendingPathComponent("Backup", isDirectory: true)
        try fm.createDirectory(at: samplesFolder, withIntermediateDirectories: true)
        try fm.createDirectory(at: backupFolder, withIntermediateDirectories: true)

        let sampleData = Data(repeating: 0x41, count: 5000)
        let backupData = Data(repeating: 0x42, count: 2000)
        let alsData = Data(repeating: 0x43, count: 1000)
        let exportData = Data(repeating: 0x44, count: 800)

        try sampleData.write(to: samplesFolder.appendingPathComponent("vocal.wav"))
        try backupData.write(to: backupFolder.appendingPathComponent("backup.als"))
        try alsData.write(to: projectFolder.appendingPathComponent("Project.als"))
        try exportData.write(to: projectFolder.appendingPathComponent("Demo.mp3"))

        let store = ProjectOffloadStore.shared
        let breakdown = await store.calculateSize(for: projectFolder)

        XCTAssertEqual(breakdown.samplesBytes, 5000)
        XCTAssertEqual(breakdown.backupBytes, 2000)
        XCTAssertEqual(breakdown.alsBytes, 1000)
        XCTAssertEqual(breakdown.exportsBytes, 800)
        XCTAssertEqual(breakdown.totalBytes, 8800)
        XCTAssertEqual(breakdown.estimatedSavings, 8000)
    }

    func testOffloadAndRestoreCyclePreservesAudioExportAndReclaimsSpace() async throws {
        let fm = FileManager.default
        let projectFolder = tempDir.appendingPathComponent("Full Ableton Song", isDirectory: true)
        let samplesFolder = projectFolder.appendingPathComponent("Samples/Recorded", isDirectory: true)
        let backupFolder = projectFolder.appendingPathComponent("Backup", isDirectory: true)
        try fm.createDirectory(at: samplesFolder, withIntermediateDirectories: true)
        try fm.createDirectory(at: backupFolder, withIntermediateDirectories: true)

        let sampleURL = samplesFolder.appendingPathComponent("take1.wav")
        let backupURL = backupFolder.appendingPathComponent("Full Ableton Song [2026-05-12].als")
        let alsURL = projectFolder.appendingPathComponent("Full Ableton Song.als")
        let exportURL = projectFolder.appendingPathComponent("Full Ableton Song v1.mp3")

        try "SampleAudio".data(using: .utf8)!.write(to: sampleURL)
        try "BackupALS".data(using: .utf8)!.write(to: backupURL)
        try "CurrentALS".data(using: .utf8)!.write(to: alsURL)
        try "AudioExport".data(using: .utf8)!.write(to: exportURL)

        // 1. Initial scan
        let initialProject = await ProjectScanner.scanProject(at: projectFolder)
        XCTAssertNotNil(initialProject)
        XCTAssertFalse(initialProject?.isOffloaded ?? true)
        XCTAssertEqual(initialProject?.tracks.count, 1)

        // 2. Offload project
        let store = ProjectOffloadStore.shared
        let archiveFolder = tempDir.appendingPathComponent("CloudArchives", isDirectory: true)
        let archiveDestination = archiveFolder.appendingPathComponent("Full Ableton Song.zip")

        _ = try await store.offloadProject(
            project: initialProject!,
            customArchiveDestination: archiveDestination,
            keepAudioExport: true
        )

        XCTAssertTrue(fm.fileExists(atPath: archiveDestination.path))
        XCTAssertFalse(fm.fileExists(atPath: alsURL.path), "ALS file should be removed from local folder")
        XCTAssertFalse(fm.fileExists(atPath: sampleURL.path), "Sample file should be removed from local folder")
        XCTAssertTrue(fm.fileExists(atPath: exportURL.path), "Audio export must remain in local folder")

        // 3. Scan offloaded project
        let offloadedScanned = await ProjectScanner.scanProject(at: projectFolder)
        XCTAssertNotNil(offloadedScanned)
        XCTAssertTrue(offloadedScanned?.isOffloaded ?? false)
        XCTAssertEqual(offloadedScanned?.tracks.count, 1, "Audio export must be accessible for auditioning while offloaded")
        XCTAssertEqual(offloadedScanned?.primaryTrack?.displayName, "Full Ableton Song v1")

        // 4. Restore project
        try await store.restoreProject(project: offloadedScanned!)

        XCTAssertTrue(fm.fileExists(atPath: alsURL.path), "ALS file should be restored")
        XCTAssertTrue(fm.fileExists(atPath: sampleURL.path), "Sample file should be restored")
        XCTAssertTrue(fm.fileExists(atPath: backupURL.path), "Backup file should be restored")
        XCTAssertFalse(fm.fileExists(atPath: projectFolder.appendingPathComponent(ProjectOffloadStore.markerFileName).path), "Marker should be cleaned up")

        // 5. Scan restored project
        let restoredScanned = await ProjectScanner.scanProject(at: projectFolder)
        XCTAssertNotNil(restoredScanned)
        XCTAssertFalse(restoredScanned?.isOffloaded ?? true)
        XCTAssertEqual(restoredScanned?.versions.count, 1)
    }
}
