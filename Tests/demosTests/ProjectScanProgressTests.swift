import XCTest
@testable import demos

final class ProjectScanProgressTests: XCTestCase {
    func testScannerReportsCurrentFolderAndRunningCounts() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scanner-progress-\(UUID().uuidString)", isDirectory: true)
        let collection = root.appendingPathComponent("Sketches", isDirectory: true)
        let project = collection.appendingPathComponent("Song Project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let setURL = project.appendingPathComponent("Song.als")
        try Data().write(to: setURL)
        defer { try? FileManager.default.removeItem(at: root) }

        let recorder = ProgressRecorder()
        _ = await ProjectScanner.scan(root: root) { progress in
            recorder.append(progress)
        }

        let snapshots = recorder.snapshots
        XCTAssertTrue(snapshots.contains { $0.currentFolder == "Sketches" })
        XCTAssertTrue(snapshots.contains { $0.currentFolder == "Sketches / Song Project" })
        XCTAssertEqual(snapshots.last?.projectsFound, 1)
        XCTAssertEqual(snapshots.last?.foldersScanned, 3)
        XCTAssertEqual(snapshots.last?.totalFolders, 3)
        XCTAssertEqual(snapshots.last?.fractionComplete, 1)
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ProjectScanProgress] = []

    func append(_ progress: ProjectScanProgress) {
        lock.lock()
        values.append(progress)
        lock.unlock()
    }

    var snapshots: [ProjectScanProgress] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
