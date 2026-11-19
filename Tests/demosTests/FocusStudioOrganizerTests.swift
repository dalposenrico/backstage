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

    func testClientFolderHierarchyResolution() {
        let clientBaseURL = URL(fileURLWithPath: "/Users/test/Music/MIXING - MASTERING WORK")

        // 1. Loose project directly inside client work base folder
        let looseProject = Project(
            name: "Loose Mix Project",
            folderURL: clientBaseURL.appendingPathComponent("Loose Mix Project", isDirectory: true),
            tracks: [],
            versions: [],
            creationDate: nil,
            tags: [],
            bpm: 120,
            plugins: [],
            activity: ProjectActivity()
        )

        let looseItem = FocusActionableItem(
            project: looseProject,
            metadata: ProjectMetadata(),
            todos: [],
            progress: ProjectProgress(),
            urgency: .noDeadline,
            clientBaseURL: clientBaseURL
        )

        XCTAssertTrue(looseItem.isClient)
        XCTAssertEqual(looseItem.clientName, FocusStudioOrganizer.unassignedClientName)

        // 2. Project in client subfolder
        let nestedProject = Project(
            name: "Francisco Track 1",
            folderURL: clientBaseURL
                .appendingPathComponent("Francisco Luz", isDirectory: true)
                .appendingPathComponent("Francisco Track 1", isDirectory: true),
            tracks: [],
            versions: [],
            creationDate: nil,
            tags: [],
            bpm: 120,
            plugins: [],
            activity: ProjectActivity()
        )

        let nestedItem = FocusActionableItem(
            project: nestedProject,
            metadata: ProjectMetadata(),
            todos: [],
            progress: ProjectProgress(),
            urgency: .noDeadline,
            clientBaseURL: clientBaseURL
        )

        XCTAssertTrue(nestedItem.isClient)
        XCTAssertEqual(nestedItem.clientName, "Francisco Luz")

        // 3. Project inside client work base folder, but explicitly marked .personal
        var personalMeta = ProjectMetadata()
        personalMeta.projectKind = .personal

        let personalItem = FocusActionableItem(
            project: looseProject,
            metadata: personalMeta,
            todos: [],
            progress: ProjectProgress(),
            urgency: .noDeadline,
            clientBaseURL: clientBaseURL
        )

        XCTAssertFalse(personalItem.isClient)

        // 4. Project outside client work base folder without client metadata
        let outsideProject = Project(
            name: "My Beat",
            folderURL: URL(fileURLWithPath: "/Users/test/Music/Ableton Projects/My Beat"),
            tracks: [],
            versions: [],
            creationDate: nil,
            tags: [],
            bpm: 120,
            plugins: [],
            activity: ProjectActivity()
        )

        let outsideItem = FocusActionableItem(
            project: outsideProject,
            metadata: ProjectMetadata(),
            todos: [],
            progress: ProjectProgress(),
            urgency: .noDeadline,
            clientBaseURL: clientBaseURL
        )

        XCTAssertFalse(outsideItem.isClient)
    }

    func testUnassignedClientGroupPinnedToTop() {
        let clientBaseURL = URL(fileURLWithPath: "/Users/test/Music/MIXING - MASTERING WORK")

        let looseProject = Project(
            name: "Unassigned Single",
            folderURL: clientBaseURL.appendingPathComponent("Unassigned Single", isDirectory: true),
            tracks: [],
            versions: [],
            creationDate: nil,
            tags: [],
            bpm: 120,
            plugins: [],
            activity: ProjectActivity()
        )

        let unassignedItem = FocusActionableItem(
            project: looseProject,
            metadata: ProjectMetadata(),
            todos: [],
            progress: ProjectProgress(),
            urgency: .noDeadline,
            clientBaseURL: clientBaseURL
        )

        var clientMeta = ProjectMetadata()
        clientMeta.clientName = "Apple Music"
        clientMeta.projectKind = .client

        let clientItem = FocusActionableItem(
            project: makeProject(named: "Client Album"),
            metadata: clientMeta,
            todos: [],
            progress: ProjectProgress(),
            urgency: .overdue(days: 5),
            clientBaseURL: clientBaseURL
        )

        let groups = FocusStudioOrganizer.groupByClient(
            items: [clientItem, unassignedItem],
            knownClientNames: ["Apple Music"]
        )

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.clientName, FocusStudioOrganizer.unassignedClientName)
        XCTAssertEqual(groups.last?.clientName, "Apple Music")
    }

    func testPersonalCategoryFolderInference() {
        let rootURL = URL(fileURLWithPath: "/Users/test/Music/Ableton Projects")

        // 1. Project inside Portfolio subfolder
        let portfolioProject = Project(
            name: "Best Showreel Track",
            folderURL: rootURL.appendingPathComponent("Portfolio", isDirectory: true).appendingPathComponent("Best Showreel Track", isDirectory: true),
            tracks: [],
            versions: [],
            creationDate: nil,
            tags: [],
            bpm: 124,
            plugins: [],
            activity: ProjectActivity()
        )

        let portfolioItem = FocusActionableItem(
            project: portfolioProject,
            metadata: ProjectMetadata(),
            todos: [],
            progress: ProjectProgress(),
            urgency: .noDeadline,
            rootURL: rootURL
        )

        XCTAssertEqual(portfolioItem.personalCategory, "Portfolio")

        // 2. Loose project directly in root folder
        let looseProject = Project(
            name: "Loose Sketch",
            folderURL: rootURL.appendingPathComponent("Loose Sketch", isDirectory: true),
            tracks: [],
            versions: [],
            creationDate: nil,
            tags: [],
            bpm: 120,
            plugins: [],
            activity: ProjectActivity()
        )

        let looseItem = FocusActionableItem(
            project: looseProject,
            metadata: ProjectMetadata(),
            todos: [],
            progress: ProjectProgress(),
            urgency: .noDeadline,
            rootURL: rootURL
        )

        XCTAssertEqual(looseItem.personalCategory, "Uncategorized")

        // 3. Explicit metadata override
        var customMeta = ProjectMetadata()
        customMeta.personalCategory = "EP 2026"

        let customItem = FocusActionableItem(
            project: portfolioProject,
            metadata: customMeta,
            todos: [],
            progress: ProjectProgress(),
            urgency: .noDeadline,
            rootURL: rootURL
        )

        XCTAssertEqual(customItem.personalCategory, "EP 2026")
    }

    func testPersonalCategoryGrouping() {
        let item1 = FocusActionableItem(
            project: makeProject(named: "Track 1"),
            metadata: ProjectMetadata(),
            todos: [],
            progress: ProjectProgress(),
            urgency: .dueTomorrow,
            personalCategory: "Portfolio"
        )

        let item2 = FocusActionableItem(
            project: makeProject(named: "Track 2"),
            metadata: ProjectMetadata(),
            todos: [],
            progress: ProjectProgress(),
            urgency: .overdue(days: 2),
            personalCategory: "Singles"
        )

        let item3 = FocusActionableItem(
            project: makeProject(named: "Track 3"),
            metadata: ProjectMetadata(),
            todos: [],
            progress: ProjectProgress(),
            urgency: .noDeadline,
            personalCategory: "Uncategorized"
        )

        let groups = FocusStudioOrganizer.groupByPersonalCategory(items: [item3, item1, item2])

        XCTAssertEqual(groups.count, 3)
        // Singles has overdue deadline, so it sorts first among named categories
        XCTAssertEqual(groups[0].categoryName, "Singles")
        XCTAssertEqual(groups[1].categoryName, "Portfolio")
        // Uncategorized is placed last
        XCTAssertEqual(groups[2].categoryName, "Uncategorized")
    }
}
