import XCTest
@testable import demos

final class AbletonOpeningStateTests: XCTestCase {
    func testInitializesInOpeningPhase() {
        let folderURL = URL(fileURLWithPath: "/Music/Project Alpha")
        let versionURL = folderURL.appendingPathComponent("Project Alpha.als")
        let now = Date()

        let state = AbletonOpeningState(
            projectID: folderURL,
            folderURL: folderURL,
            projectName: "Project Alpha",
            targetVersionURL: versionURL,
            startedAt: now
        )

        XCTAssertEqual(state.phase, .opening)
        XCTAssertEqual(state.projectName, "Project Alpha")
        XCTAssertEqual(state.folderURL, folderURL)
        XCTAssertEqual(state.targetVersionURL, versionURL)
        XCTAssertEqual(state.startedAt, now)
    }

    func testMatchesLoadedProjectByStandardizedURL() {
        let folderURL = URL(fileURLWithPath: "/Music/Project Alpha/../Project Alpha")
        let matchingURL = URL(fileURLWithPath: "/Music/Project Alpha")
        let differentURL = URL(fileURLWithPath: "/Music/Project Beta")

        let state = AbletonOpeningState(
            projectID: folderURL,
            folderURL: folderURL,
            projectName: "Project Alpha",
            targetVersionURL: folderURL.appendingPathComponent("v1.als")
        )

        XCTAssertTrue(state.matchesLoadedProject(folderURL: matchingURL))
        XCTAssertFalse(state.matchesLoadedProject(folderURL: differentURL))
        XCTAssertFalse(state.matchesLoadedProject(folderURL: nil))
    }

    func testTimeoutDetection() {
        let folderURL = URL(fileURLWithPath: "/Music/Project Alpha")
        let startTime = Date(timeIntervalSince1970: 1000)

        let state = AbletonOpeningState(
            projectID: folderURL,
            folderURL: folderURL,
            projectName: "Project Alpha",
            targetVersionURL: folderURL.appendingPathComponent("v1.als"),
            startedAt: startTime
        )

        // 30 seconds later -> not timed out for 60s threshold
        let midTime = Date(timeIntervalSince1970: 1030)
        XCTAssertFalse(state.hasTimedOut(at: midTime, timeoutInterval: 60))

        // 60 seconds later -> timed out
        let timeoutTime = Date(timeIntervalSince1970: 1060)
        XCTAssertTrue(state.hasTimedOut(at: timeoutTime, timeoutInterval: 60))

        // 75 seconds later -> timed out
        let laterTime = Date(timeIntervalSince1970: 1075)
        XCTAssertTrue(state.hasTimedOut(at: laterTime, timeoutInterval: 60))
    }

    func testPhaseTransitionToLoaded() {
        let folderURL = URL(fileURLWithPath: "/Music/Project Alpha")
        var state = AbletonOpeningState(
            projectID: folderURL,
            folderURL: folderURL,
            projectName: "Project Alpha",
            targetVersionURL: folderURL.appendingPathComponent("v1.als")
        )

        XCTAssertEqual(state.phase, .opening)
        state.phase = .loaded
        XCTAssertEqual(state.phase, .loaded)
    }
}
