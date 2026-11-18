import XCTest
@testable import demos

@MainActor
final class FocusStudioOrganizerTests: XCTestCase {

    private func makeProject(named name: String, latestModification: Date = Date()) -> Project {
        Project(
            name: name,
            folderURL: URL(fileURLWithPath: "/tmp/\(name)"),
            tracks: [],
            versions: [],
            creationDate: nil,
            tags: [],
            bpm: 120,
            plugins: [],
            activity: ProjectActivity(),
            latestModification: latestModification
        )
    }

    func testDeadlineUrgencyCalculation() {
        let calendar = Calendar.current
        let now = Date()

        // 1. Nil deadline -> noDeadline
        XCTAssertEqual(DeadlineUrgency.calculate(from: nil, referenceDate: now, calendar: calendar), .noDeadline)

        // 2. Yesterday -> overdue
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        XCTAssertEqual(DeadlineUrgency.calculate(from: yesterday, referenceDate: now, calendar: calendar), .overdue(days: 1))

        // 3. Three days ago -> overdue
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: now)!
        XCTAssertEqual(DeadlineUrgency.calculate(from: threeDaysAgo, referenceDate: now, calendar: calendar), .overdue(days: 3))

        // 4. Today -> dueToday
        XCTAssertEqual(DeadlineUrgency.calculate(from: now, referenceDate: now, calendar: calendar), .dueToday)

        // 5. Tomorrow -> dueTomorrow
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        XCTAssertEqual(DeadlineUrgency.calculate(from: tomorrow, referenceDate: now, calendar: calendar), .dueTomorrow)

        // 6. 3 days -> dueSoon
        let in3Days = calendar.date(byAdding: .day, value: 3, to: now)!
        XCTAssertEqual(DeadlineUrgency.calculate(from: in3Days, referenceDate: now, calendar: calendar), .dueSoon(days: 3))

        // 7. 6 days -> thisWeek
        let in6Days = calendar.date(byAdding: .day, value: 6, to: now)!
        if case .thisWeek = DeadlineUrgency.calculate(from: in6Days, referenceDate: now, calendar: calendar) {
            // expected
        } else {
            XCTFail("Expected .thisWeek for 6 days out")
        }

        // 8. 14 days -> upcoming
        let in14Days = calendar.date(byAdding: .day, value: 14, to: now)!
        if case .upcoming = DeadlineUrgency.calculate(from: in14Days, referenceDate: now, calendar: calendar) {
            // expected
        } else {
            XCTFail("Expected .upcoming for 14 days out")
        }
    }

    func testDeadlineUrgencySortingOrder() {
        let calendar = Calendar.current
        let now = Date()

        let overdue = DeadlineUrgency.calculate(from: calendar.date(byAdding: .day, value: -2, to: now)!, referenceDate: now)
        let today = DeadlineUrgency.calculate(from: now, referenceDate: now)
        let tomorrow = DeadlineUrgency.calculate(from: calendar.date(byAdding: .day, value: 1, to: now)!, referenceDate: now)
        let soon = DeadlineUrgency.calculate(from: calendar.date(byAdding: .day, value: 3, to: now)!, referenceDate: now)
        let none = DeadlineUrgency.noDeadline

        XCTAssertTrue(overdue < today)
        XCTAssertTrue(today < tomorrow)
        XCTAssertTrue(tomorrow < soon)
        XCTAssertTrue(soon < none)
    }

    func testClientAndPersonalClassification() {
        let clientProject = makeProject(named: "Client Anthem")

        var clientMeta = ProjectMetadata()
        clientMeta.projectKind = .client
        clientMeta.clientName = "Sarah Connor"

        let clientItem = FocusActionableItem(
            project: clientProject,
            metadata: clientMeta,
            todos: [],
            progress: ProjectProgress(),
            urgency: .dueToday
        )
        XCTAssertTrue(clientItem.isClient)
        XCTAssertEqual(clientItem.clientName, "Sarah Connor")

        let personalProject = makeProject(named: "Ambient 01")

        let personalItem = FocusActionableItem(
            project: personalProject,
            metadata: ProjectMetadata(),
            todos: [],
            progress: ProjectProgress(),
            urgency: .noDeadline
        )
        XCTAssertFalse(personalItem.isClient)
    }

    func testClientGrouping() {
        var metaA = ProjectMetadata()
        metaA.clientName = "Warner Music"
        metaA.projectKind = .client

        var metaB = ProjectMetadata()
        metaB.clientName = "Warner Music"
        metaB.projectKind = .client

        var metaC = ProjectMetadata()
        metaC.clientName = "Indie Band"
        metaC.projectKind = .client

        let item1 = FocusActionableItem(
            project: makeProject(named: "Single A"),
            metadata: metaA,
            todos: [],
            progress: ProjectProgress(),
            urgency: .dueToday
        )
        let item2 = FocusActionableItem(
            project: makeProject(named: "Single B"),
            metadata: metaB,
            todos: [],
            progress: ProjectProgress(),
            urgency: .dueTomorrow
        )
        let item3 = FocusActionableItem(
            project: makeProject(named: "EP Track"),
            metadata: metaC,
            todos: [],
            progress: ProjectProgress(),
            urgency: .overdue(days: 1)
        )

        let groups = FocusStudioOrganizer.groupByClient(items: [item1, item2, item3])

        XCTAssertEqual(groups.count, 2)
        // Group with overdue deadline (Indie Band) should sort before Warner Music
        XCTAssertEqual(groups.first?.clientName, "Indie Band")
        XCTAssertEqual(groups.last?.clientName, "Warner Music")
        XCTAssertEqual(groups.last?.items.count, 2)
    }
}
