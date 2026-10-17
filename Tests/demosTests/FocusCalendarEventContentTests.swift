import XCTest
@testable import demos

final class FocusCalendarEventContentTests: XCTestCase {
    func testFocusURLRoundTripsPrivateProjectPath() throws {
        let path = "/Users/producer/Music/Banan Project"
        let url = try XCTUnwrap(FocusCalendarEventContent.url(projectPath: path))

        XCTAssertEqual(FocusCalendarEventContent.projectPath(from: url), path)
        XCTAssertEqual(url.scheme, "goodvibrations")
        XCTAssertEqual(url.host, "focus")
    }

    func testWakeURLIncludesSessionDuration() {
        let event = ScheduledFocusEvent(
            eventIdentifier: "event-1",
            title: "Focus · Banan",
            projectPath: "/Music/Banan",
            startDate: Date(),
            endDate: Date().addingTimeInterval(50 * 60),
            calendarTitle: "Work"
        )

        let url = FocusCalendarEventContent.wakeURL(for: event)
        XCTAssertEqual(FocusCalendarEventContent.projectPath(from: url), "/Music/Banan")
        XCTAssertEqual(FocusCalendarEventContent.durationMinutes(from: url), 50)
    }

    func testCalendarNotesContainOpenChecklist() {
        let notes = FocusCalendarEventContent.notes(
            projectName: "Banan",
            taskTitles: ["Fix the drop", "Bounce a new mix"]
        )

        XCTAssertTrue(notes.contains("focus session for Banan"))
        XCTAssertTrue(notes.contains("☐ Fix the drop"))
        XCTAssertTrue(notes.contains("☐ Bounce a new mix"))
    }

    func testPlannerDragItemRoundTripsForTaskAndEventMoves() throws {
        let item = FocusPlannerDragItem(
            kind: .event,
            title: "Fix the drop",
            projectPath: "/Music/Banan",
            projectName: "Banan",
            eventIdentifier: "event-42"
        )

        let encoded = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(FocusPlannerDragItem.self, from: encoded), item)
    }
}
