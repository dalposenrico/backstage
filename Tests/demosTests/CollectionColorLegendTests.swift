import XCTest
@testable import demos

@MainActor
final class CollectionColorLegendTests: XCTestCase {
    func testLegendUsesInheritedCollectionColorsAndRemovesDuplicates() throws {
        let suiteName = "CollectionColorLegendTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let originals = URL(fileURLWithPath: "/Music/Originals")
        let sketches = URL(fileURLWithPath: "/Music/Sketches & Experiments")
        let store = CollectionColorStore(defaults: defaults, storageKey: "legendColors")
        store.setColor(.pink, for: originals)
        store.setColor(.green, for: sketches)

        let items = store.legendItems(for: [
            originals.appendingPathComponent("First Project"),
            originals.appendingPathComponent("Second Project"),
            sketches.appendingPathComponent("Idea"),
            URL(fileURLWithPath: "/Music/Uncolored/Project")
        ])

        XCTAssertEqual(items.map(\.title), ["Originals", "Sketches & Experiments"])
        XCTAssertEqual(items.map(\.color), [.pink, .green])
    }
}
