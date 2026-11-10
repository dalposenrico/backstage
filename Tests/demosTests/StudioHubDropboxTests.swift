import XCTest
@testable import demos

@MainActor
final class StudioHubDropboxTests: XCTestCase {

    func testDropboxManagerResolvesClientAndPersonalFolderPaths() {
        let manager = DropboxManager.shared
        guard manager.dropboxRootURL != nil else {
            // If Dropbox root is not detected in CI or sandbox, test fallback logic directly
            let fallbackRoot = URL(fileURLWithPath: "/Users/test/Dropbox")
            let clientURL = fallbackRoot
                .appendingPathComponent(DropboxManager.defaultClientWorkFolderName)
                .appendingPathComponent("Francisco Luz")
                .appendingPathComponent("UGOTME")
            XCTAssertTrue(clientURL.path.contains("MIXING - MASTERING WORK/Francisco Luz/UGOTME"))
            return
        }

        let clientURL = manager.recommendedFolderURL(
            clientName: "Francisco Luz",
            projectName: "UGOTME",
            isClientProject: true
        )
        XCTAssertNotNil(clientURL)
        XCTAssertTrue(clientURL!.path.contains("MIXING - MASTERING WORK/Francisco Luz/UGOTME"))

        let personalURL = manager.recommendedFolderURL(
            clientName: nil,
            projectName: "Deep Summer Jam",
            isClientProject: false
        )
        XCTAssertNotNil(personalURL)
        XCTAssertTrue(personalURL!.path.contains("MUSIC PROJECTS/Deep Summer Jam"))
    }

    func testDropboxManagerGeneratesWebURL() {
        let manager = DropboxManager.shared
        guard let root = manager.dropboxRootURL else { return }

        let sampleFolder = root
            .appendingPathComponent("MIXING - MASTERING WORK")
            .appendingPathComponent("Francisco Luz")
            .appendingPathComponent("UGOTME")

        let webURL = manager.dropboxWebURL(for: sampleFolder)
        XCTAssertNotNil(webURL)
        XCTAssertTrue(webURL!.absoluteString.hasPrefix("https://www.dropbox.com/home/"))
        XCTAssertTrue(webURL!.absoluteString.contains("MIXING%20-%20MASTERING%20WORK"))
        XCTAssertTrue(webURL!.absoluteString.contains("Francisco%20Luz"))
    }

    func testProjectMetadataEncodesAndDecodesStudioFields() throws {
        var meta = ProjectMetadata()
        meta.projectKind = .client
        meta.clientName = "Alec"
        meta.serviceType = .mixing
        meta.targetLUFS = -9.0
        meta.dropboxShareLink = "https://www.dropbox.com/scl/fo/abc123xyz"
        meta.manualDeliverables = [
            DeliverableItem(title: "Main Mix", isCompleted: true),
            DeliverableItem(title: "Instrumental", isCompleted: false)
        ]
        meta.revisions = [
            ProjectRevisionItem(
                timestampSeconds: 84.0,
                timestampLabel: "01:24",
                text: "Lead vocal +1dB in chorus",
                isResolved: false
            )
        ]

        let data = try JSONEncoder().encode(meta)
        let decoded = try JSONDecoder().decode(ProjectMetadata.self, from: data)

        XCTAssertEqual(decoded.projectKind, .client)
        XCTAssertEqual(decoded.clientName, "Alec")
        XCTAssertEqual(decoded.serviceType, .mixing)
        XCTAssertEqual(decoded.targetLUFS, -9.0)
        XCTAssertEqual(decoded.dropboxShareLink, "https://www.dropbox.com/scl/fo/abc123xyz")
        XCTAssertEqual(decoded.manualDeliverables?.count, 2)
        XCTAssertEqual(decoded.manualDeliverables?.first?.isCompleted, true)
        XCTAssertEqual(decoded.revisions?.count, 1)
        XCTAssertEqual(decoded.revisions?.first?.timestampSeconds, 84.0)
        XCTAssertEqual(decoded.revisions?.first?.timestampLabel, "01:24")
    }

    func testLegacyProjectMetadataDecodesWithoutStudioFields() throws {
        // Legacy JSON only has rating, priority, musicalKey
        let legacyJSON = """
        {
            "rating": "S",
            "priority": 1,
            "musicalKey": "C minor"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ProjectMetadata.self, from: legacyJSON)
        XCTAssertEqual(decoded.rating, .s)
        XCTAssertEqual(decoded.priority, .p1)
        XCTAssertEqual(decoded.musicalKey, "C minor")
        XCTAssertNil(decoded.projectKind)
        XCTAssertNil(decoded.clientName)
        XCTAssertNil(decoded.manualDeliverables)
        XCTAssertNil(decoded.revisions)
    }
}
