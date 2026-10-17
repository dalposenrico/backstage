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
