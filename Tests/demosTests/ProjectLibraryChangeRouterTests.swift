import XCTest
@testable import demos

final class ProjectLibraryChangeRouterTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/Music")
    private let first = URL(fileURLWithPath: "/Music/Originals/First Project")
    private let second = URL(fileURLWithPath: "/Music/Sketches/Second Project")

    func testBackupAndExportChangesRefreshOnlyTheirProjects() {
        let result = ProjectLibraryChangeRouter.projectFoldersToRefresh(
            changedURLs: [
                first.appendingPathComponent("Backup/First-2026-08-20.als"),
                second.appendingPathComponent("Exports/Second v4.wav")
            ],
            projectFolderURLs: [first, second],
            rootURL: root
        )

        XCTAssertEqual(result, Set([first, second]))
    }

    func testNewUnrecognizedFolderRequestsFullScan() {
        let result = ProjectLibraryChangeRouter.projectFoldersToRefresh(
            changedURLs: [root.appendingPathComponent("Originals/New Project/New Project.als")],
            projectFolderURLs: [first, second],
            rootURL: root
        )

        XCTAssertNil(result)
    }

    func testHiddenMetadataNoiseIsIgnored() {
        let result = ProjectLibraryChangeRouter.projectFoldersToRefresh(
            changedURLs: [root.appendingPathComponent(".DS_Store")],
            projectFolderURLs: [first, second],
            rootURL: root
        )

        XCTAssertEqual(result, [])
    }
}
