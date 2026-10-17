import XCTest
@testable import demos

final class LibraryLoadPresentationTests: XCTestCase {
    private let folder = URL(fileURLWithPath: "/Music/Projects")

    func testNoFolderClearlyRequestsAChoice() {
        XCTAssertEqual(
            LibraryLoadPresentation.resolve(
                rootFolderURL: nil,
                unavailableFolderPath: nil,
                isScanning: false,
                hasCompletedScan: false,
                projectCount: 0
            ),
            .chooseFolder
        )
    }

    func testRestoredFolderShowsLoadingBeforeAndDuringInitialScan() {
        for isScanning in [false, true] {
            XCTAssertEqual(
                LibraryLoadPresentation.resolve(
                    rootFolderURL: folder,
                    unavailableFolderPath: nil,
                    isScanning: isScanning,
                    hasCompletedScan: false,
                    projectCount: 0
                ),
                .loading(folderName: "Projects")
            )
        }
    }

    func testCompletedEmptyScanIsDifferentFromLoading() {
        XCTAssertEqual(
            LibraryLoadPresentation.resolve(
                rootFolderURL: folder,
                unavailableFolderPath: nil,
                isScanning: false,
                hasCompletedScan: true,
                projectCount: 0
            ),
            .noProjects(folderName: "Projects")
        )
    }

    func testRefreshKeepsExistingLibraryVisible() {
        XCTAssertEqual(
            LibraryLoadPresentation.resolve(
                rootFolderURL: folder,
                unavailableFolderPath: nil,
                isScanning: true,
                hasCompletedScan: true,
                projectCount: 12
            ),
            .updating(folderName: "Projects")
        )
    }
}
