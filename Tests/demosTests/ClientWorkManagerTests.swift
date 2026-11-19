import XCTest
@testable import demos

@MainActor
final class ClientWorkManagerTests: XCTestCase {

    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        super.tearDown()
    }

    func testBaseFolderResolutionAndCustomPath() {
        let manager = ClientWorkManager.shared
        let originalCustom = manager.customClientWorkFolderPath
        defer {
            manager.customClientWorkFolderPath = originalCustom
        }

        manager.customClientWorkFolderPath = tempDir.path
        XCTAssertEqual(manager.clientWorkBaseURL.path, tempDir.path)
        XCTAssertTrue(manager.baseFolderExistsOnDisk)
    }

    func testCreateClientFolderOnDisk() throws {
        let manager = ClientWorkManager.shared
        let originalCustom = manager.customClientWorkFolderPath
        defer {
            manager.customClientWorkFolderPath = originalCustom
        }

        manager.customClientWorkFolderPath = tempDir.path
        let clientFolder = try manager.createClientFolder(named: "Francisco Luz")

        XCTAssertTrue(FileManager.default.fileExists(atPath: clientFolder.path))
        XCTAssertEqual(clientFolder.lastPathComponent, "Francisco Luz")
        XCTAssertTrue(manager.discoveredClientNames.contains("Francisco Luz"))
    }

    func testMoveProjectToClientFolder() throws {
        let manager = ClientWorkManager.shared
        let originalCustom = manager.customClientWorkFolderPath
        defer {
            manager.customClientWorkFolderPath = originalCustom
        }

        manager.customClientWorkFolderPath = tempDir.path

        // Create a dummy source project
        let sourceProjectFolder = tempDir.appendingPathComponent("Original Song Project", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceProjectFolder, withIntermediateDirectories: true)
        let dummyFile = sourceProjectFolder.appendingPathComponent("Song.als")
        try "als content".write(to: dummyFile, atomically: true, encoding: .utf8)

        let project = Project(
            name: "Original Song Project",
            folderURL: sourceProjectFolder,
            tracks: [],
            versions: [],
            creationDate: nil,
            tags: [],
            bpm: 120,
            plugins: [],
            activity: ProjectActivity()
        )

        let metaStore = ProjectMetadataStore()
        let todoStore = ProjectTodoStore()
        let progressStore = ProjectProgressStore()

        metaStore.setRating(.s, for: project)
        todoStore.add("Finish mix", to: project)
        progressStore.setStage(.mix, for: project)

        // Move to client "Sarah Connor"
        let destURL = try manager.moveProject(
            project,
            toClient: "Sarah Connor",
            metadataStore: metaStore,
            todoStore: todoStore,
            progressStore: progressStore
        )

        // 1. Source no longer exists
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceProjectFolder.path))

        // 2. Destination exists with contents
        XCTAssertTrue(FileManager.default.fileExists(atPath: destURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destURL.appendingPathComponent("Song.als").path))
        XCTAssertEqual(destURL.deletingLastPathComponent().lastPathComponent, "Sarah Connor")

        // 3. Metadata migrated
        let newProject = Project(
            name: "Original Song Project",
            folderURL: destURL,
            tracks: [],
            versions: [],
            creationDate: nil,
            tags: [],
            bpm: 120,
            plugins: [],
            activity: ProjectActivity()
        )
        let migratedMeta = metaStore.metadata(for: newProject)
        XCTAssertEqual(migratedMeta.rating, .s)
        XCTAssertEqual(migratedMeta.projectKind, .client)
        XCTAssertEqual(migratedMeta.clientName, "Sarah Connor")

        // 4. Todos migrated
        let migratedTodos = todoStore.todos(for: newProject)
        XCTAssertEqual(migratedTodos.count, 1)
        XCTAssertEqual(migratedTodos.first?.title, "Finish mix")

        // 5. Progress migrated
        let migratedProg = progressStore.progress(for: newProject)
        XCTAssertEqual(migratedProg.stage, .mix)
    }

    func testClientGroupingWithKnownClientFolders() {
        let items: [FocusActionableItem] = []
        let known = ["Client A", "Client B"]

        let groups = FocusStudioOrganizer.groupByClient(items: items, knownClientNames: known)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map(\.clientName).sorted(), ["Client A", "Client B"])
        XCTAssertTrue(groups.allSatisfy { $0.items.isEmpty })
    }

    func testDiscoveredClientsFiltersOutDirectProjectFolders() throws {
        let manager = ClientWorkManager.shared
        let originalCustom = manager.customClientWorkFolderPath
        defer {
            manager.customClientWorkFolderPath = originalCustom
        }

        manager.customClientWorkFolderPath = tempDir.path

        // 1. Create a client directory (contains no .als directly)
        let clientFolder = tempDir.appendingPathComponent("Real Client", isDirectory: true)
        try FileManager.default.createDirectory(at: clientFolder, withIntermediateDirectories: true)

        // 2. Create an Ableton project directly inside base folder (contains .als)
        let projectFolder = tempDir.appendingPathComponent("Loose Ableton Project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)
        let alsFile = projectFolder.appendingPathComponent("Song.als")
        try "als dummy".write(to: alsFile, atomically: true, encoding: .utf8)

        manager.refreshDiscoveredClients()

        XCTAssertTrue(manager.discoveredClientNames.contains("Real Client"))
        XCTAssertFalse(manager.discoveredClientNames.contains("Loose Ableton Project"), "Ableton project folders with .als files must not be treated as client names")
    }
}
