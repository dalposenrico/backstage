import XCTest
@testable import demos

@MainActor
final class ComparisonMarkerStoreTests: XCTestCase {
    func testPersistsNotesAndPreferredVersionsPerProject() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("comparison-markers-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let project = makeProject(named: "Song A")
        let sourcePath = "/tmp/song-a-v3.wav"

        let store = ComparisonMarkerStore(fileURL: fileURL)
        var marker = store.add(to: project, at: 0.42, title: "Drop")
        marker.note = "Keep the drums from v3"
        marker.preferredSourcePaths = [sourcePath]
        store.update(marker, for: project)

        let reloaded = ComparisonMarkerStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.markers(for: project).first?.note, "Keep the drums from v3")
        XCTAssertEqual(reloaded.markers(for: project).first?.preferredSourcePaths, [sourcePath])
    }

    func testAbletonImportDoesNotDuplicateTheSameLocator() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("comparison-markers-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let project = makeProject(named: "Song B")
        let store = ComparisonMarkerStore(fileURL: fileURL)
        let locator = AbletonLocator(timeInBeats: 64, name: "Drop", annotation: "Big transition")

        XCTAssertEqual(store.importAbleton([(0.5, locator)], into: project), 1)
        XCTAssertEqual(store.importAbleton([(0.5, locator)], into: project), 0)
        XCTAssertEqual(store.markers(for: project).count, 1)
    }

    func testStoresASeparatePositionForEachVersion() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("comparison-markers-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let project = makeProject(named: "Song C")
        let newestPath = "/tmp/song-c-v3.wav"
        let olderPath = "/tmp/song-c-v2.wav"

        let store = ComparisonMarkerStore(fileURL: fileURL)
        var marker = store.add(to: project, at: 0.32, sourcePath: newestPath, title: "Drop")
        marker.setPosition(0.46, for: olderPath)
        store.update(marker, for: project)

        let reloaded = ComparisonMarkerStore(fileURL: fileURL)
        let saved = try! XCTUnwrap(reloaded.markers(for: project).first)
        XCTAssertEqual(saved.position(for: newestPath, legacySourcePath: nil), 0.32)
        XCTAssertEqual(saved.position(for: olderPath, legacySourcePath: nil), 0.46)
        XCTAssertNil(saved.position(for: "/tmp/song-c-v1.wav", legacySourcePath: nil))
    }

    func testLegacySharedPositionOnlyAppearsOnNewestVersion() throws {
        let marker = ComparisonMarker(fraction: 0.4, title: "Break")

        XCTAssertEqual(marker.position(for: "/tmp/newest.wav", legacySourcePath: "/tmp/newest.wav"), 0.4)
        XCTAssertNil(marker.position(for: "/tmp/older.wav", legacySourcePath: "/tmp/newest.wav"))
    }

    func testBeatGridSnapsUsingEachTracksDuration() {
        let duration = 120.0
        let bpm = 120.0

        XCTAssertEqual(
            ComparisonBeatGrid.snappedFraction(0.103, duration: duration, bpm: bpm),
            0.10416666666666667,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            ComparisonBeatGrid.snappedFraction(-1, duration: duration, bpm: bpm),
            0
        )
        XCTAssertEqual(
            ComparisonBeatGrid.snappedFraction(2, duration: duration, bpm: bpm),
            1
        )
    }

    func testSectionRangesAndAssemblyPersistTogether() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("comparison-workspace-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let project = makeProject(named: "Song D")
        let sourcePath = "/tmp/song-d-v4.wav"

        let store = ComparisonMarkerStore(fileURL: fileURL)
        var marker = store.add(to: project, at: 0.20, sourcePath: sourcePath, title: "Break", kind: .section)
        marker.setRange(start: 0.20, end: 0.36, for: sourcePath)
        store.update(marker, for: project)
        store.addToAssembly(marker, sourcePath: sourcePath, for: project)

        let reloaded = ComparisonMarkerStore(fileURL: fileURL)
        let savedMarker = try XCTUnwrap(reloaded.markers(for: project).first)
        let savedRange = try XCTUnwrap(savedMarker.range(for: sourcePath, legacySourcePath: nil))
        XCTAssertEqual(savedRange.lowerBound, 0.20)
        XCTAssertEqual(savedRange.upperBound, 0.36)
        XCTAssertEqual(savedMarker.kind, .section)
        XCTAssertEqual(reloaded.assembly(for: project).first?.markerID, marker.id)
        XCTAssertEqual(reloaded.assembly(for: project).first?.sourcePath, sourcePath)
    }

    func testMarkerRemainsAPointWithoutASectionRange() {
        var marker = ComparisonMarker(fraction: 0.25, title: "Transition", kind: .marker)
        marker.setPosition(0.5, for: "/tmp/version.wav")

        XCTAssertEqual(marker.position(for: "/tmp/version.wav", legacySourcePath: nil), 0.5)
        XCTAssertNil(marker.range(for: "/tmp/version.wav", legacySourcePath: nil))
    }

    private func makeProject(named name: String) -> Project {
        Project(
            name: name,
            folderURL: URL(fileURLWithPath: "/tmp/\(name)"),
            tracks: [],
            versions: [],
            creationDate: nil,
            tags: [],
            bpm: 120,
            plugins: [],
            activity: ProjectActivity()
        )
    }
}
