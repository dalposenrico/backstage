import XCTest
@testable import demos

final class AbletonSessionDetectorTests: XCTestCase {
    func testMatchesExactAbletonVersionInsideWindowTitle() {
        let current = project("Idea July 17", path: "/Music/Idea July 17", versions: ["idea july 17 v5"])
        let other = project("Idea July 18", path: "/Music/Idea July 18", versions: ["idea july 18 v2"])

        let match = AbletonSessionDetector.matchingProject(
            in: [other, current],
            windowTitles: ["idea july 17 v5 — Ableton Live 12 Suite"]
        )

        XCTAssertEqual(match?.folderURL, current.folderURL)
    }

    func testPrefersSpecificVersionOverShorterProjectName() {
        let broad = project("Dreamy Glow", path: "/Music/Broad", versions: ["Dreamy Glow"])
        let exact = project("Dreamy Glow Fred Again", path: "/Music/Exact", versions: ["Dreamy Glow Fred Again 2"])

        let match = AbletonSessionDetector.matchingProject(
            in: [broad, exact],
            windowTitles: ["Dreamy Glow Fred Again 2 | Ableton Live"]
        )

        XCTAssertEqual(match?.folderURL, exact.folderURL)
    }

    func testDoesNotGuessWhenStrongestMatchIsAmbiguous() {
        let first = project("Shared", path: "/Music/One", versions: ["shared v3"])
        let second = project("Shared", path: "/Music/Two", versions: ["shared v3"])

        XCTAssertNil(AbletonSessionDetector.matchingProject(
            in: [first, second],
            windowTitles: ["shared v3 - Ableton Live"]
        ))
    }

    func testMatchesProjectFromDocumentOpenedOutsideHQ() {
        let project = project("Dreamy Glow", path: "/Music/Dreamy Glow Project", versions: ["Dreamy Glow 4"])
        let openedURL = project.folderURL.appendingPathComponent("Dreamy Glow 4.als")

        XCTAssertEqual(
            AbletonSessionDetector.matchingProject(in: [project], loadedDocumentURLs: [openedURL])?.folderURL,
            project.folderURL
        )
    }

    func testUnrelatedPluginWindowFallsBackToLoadedDocument() {
        let project = project("Dreamy Glow", path: "/Music/Dreamy Glow Project", versions: ["Dreamy Glow 4"])
        let openedURL = project.folderURL.appendingPathComponent("Dreamy Glow 4.als")

        let match = AbletonSessionDetector.activeProject(
            in: [project],
            windowTitles: ["FabFilter Pro-L 2", "Snapback"],
            loadedDocumentURLs: [openedURL]
        )

        XCTAssertEqual(match?.folderURL, project.folderURL)
    }

    func testRecoveredBaseFileMatchesItsRealProjectVersion() {
        let project = project(
            "Dreamy Glow Fred Again",
            path: "/Music/Sketches/Dreamy Glow Fred Again Project",
            versions: ["dreamy glow fred again_4_new_bridge"]
        )
        let recoveryURL = URL(fileURLWithPath:
            "/Users/me/Library/Preferences/Ableton/Live 12.4.3/BaseFiles/dreamy glow fred again_4_new_bridge-1.als"
        )

        XCTAssertEqual(
            AbletonSessionDetector.matchingProject(in: [project], loadedDocumentURLs: [recoveryURL])?.folderURL,
            project.folderURL
        )
    }

    func testLogReaderOnlyReturnsDocumentsLoadedSinceAbletonLaunched() throws {
        let launchDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-21T14:00:00Z"))
        let log = """
        2026-08-21T13:59:59.000000Z: info: Loading document "/Music/Old/Old.als"
        2026-08-21T14:01:00.000000Z: info: Loading document "/Music/New/New.als"
        2026-08-21T14:02:00.000000Z: info: Loading document "/Music/Ableton/User Library/Defaults/Creating Tracks/Audio Track/Default Audio Track.als"
        """

        XCTAssertEqual(
            AbletonSessionDetector.loadedDocuments(in: log, since: launchDate).map(\.path),
            ["/Music/New/New.als"]
        )
    }

    func testLogReaderReturnsBothLoadingAndSavingDocuments() throws {
        let launchDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-21T14:00:00Z"))
        let log = """
        2026-08-21T14:01:00.000000Z: info: Loading document "/Downloads/Collab/Collab_1.als"
        2026-08-21T14:05:00.000000Z: info: Saving document "/Downloads/Collab/Collab_2.als"
        """

        let docs = AbletonSessionDetector.loadedDocuments(in: log, since: launchDate).map(\.path)
        XCTAssertEqual(docs, ["/Downloads/Collab/Collab_2.als", "/Downloads/Collab/Collab_1.als"])
    }

    func testProjectFolderExtraction() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let docURL = tempDir.appendingPathComponent("Track_1.als")
        let extracted = AbletonSessionDetector.projectFolder(forDocumentURL: docURL)
        XCTAssertEqual(extracted?.standardizedFileURL.path, tempDir.standardizedFileURL.path)

        // Backup folder unwrapping
        let backupDir = tempDir.appendingPathComponent("Backup")
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let backupDocURL = backupDir.appendingPathComponent("Track_backup.als")
        let backupExtracted = AbletonSessionDetector.projectFolder(forDocumentURL: backupDocURL)
        XCTAssertEqual(backupExtracted?.standardizedFileURL.path, tempDir.standardizedFileURL.path)
    }

    @MainActor
    func testAppStoreExternalProjectClassificationAndDisplayLocation() {
        let store = AppStore()
        store.rootFolderURL = URL(fileURLWithPath: "/Users/test/Music/Music Projects")

        let internalProject = project("Internal Song", path: "/Users/test/Music/Music Projects/Sketches/Internal Song", versions: ["v1"])
        let externalProject = project("Collab Download", path: "/Users/test/Downloads/Collab Download", versions: ["v1"])

        XCTAssertFalse(store.isExternalProject(internalProject))
        XCTAssertTrue(store.isExternalProject(externalProject))

        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let homeExternal = project("Download", path: "\(home)/Downloads/ProjectX", versions: ["v1"])
        XCTAssertEqual(store.displayLocation(for: homeExternal), "~/Downloads/ProjectX")
    }

    func testLogReaderHandlesNoiseAndUppercaseALSWithFastFilter() throws {
        let launchDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-21T14:00:00Z"))
        let log = """
        2026-08-21T14:01:00.000000Z: info: AudioEngine: buffer underrun detected
        2026-08-21T14:01:05.000000Z: info: Loading document "/Music/Drafts/Readme.txt"
        2026-08-21T14:01:10.000000Z: info: Loading document "/Music/Drafts/UpperCaseSet.ALS"
        2026-08-21T14:01:15.000000Z: info: Plugin scanned without extension .als in comment
        """

        let docs = AbletonSessionDetector.loadedDocuments(in: log, since: launchDate).map(\.path)
        XCTAssertEqual(docs, ["/Music/Drafts/UpperCaseSet.ALS"])
    }

    func testBackgroundCGEventTapStartsDisablesAndStopsCleanly() {
        let tap = BackgroundCGEventTap()
        tap.start(
            name: "test.background.tap",
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            initiallyEnabled: false,
            handler: { _, _, event in Unmanaged.passRetained(event) }
        )
        tap.setEnabled(true)
        tap.setEnabled(false)
        tap.stop()
    }

    private func project(_ name: String, path: String, versions: [String]) -> Project {
        Project(
            name: name,
            folderURL: URL(fileURLWithPath: path),
            tracks: [],
            versions: versions.map {
                AbletonVersion(url: URL(fileURLWithPath: path).appendingPathComponent($0 + ".als"), modificationDate: nil, creationDate: nil)
            },
            creationDate: nil,
            tags: [],
            bpm: nil,
            plugins: [],
            activity: ProjectActivity()
        )
    }
}
