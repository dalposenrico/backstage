import XCTest
@testable import demos

final class ProjectNameGeneratorTests: XCTestCase {
    func testEmptyInputProducesNoSuggestions() {
        XCTAssertTrue(ProjectNameGenerator.generate(vibe: "", tags: []).isEmpty)
    }

    func testGeneratesRequestedNumberOfUniqueSuggestions() {
        let suggestions = ProjectNameGenerator.generate(
            vibe: "dreamy",
            tags: ["night drive", "blue"],
            count: 12
        )

        XCTAssertEqual(suggestions.count, 12)
        XCTAssertEqual(Set(suggestions).count, suggestions.count)
    }

    func testSameInputAndVariationAreRepeatable() {
        let first = ProjectNameGenerator.generate(vibe: "warm", tags: ["summer"], variation: 4)
        let second = ProjectNameGenerator.generate(vibe: "warm", tags: ["summer"], variation: 4)

        XCTAssertEqual(first, second)
    }

    func testNewVariationProducesFreshSuggestions() {
        let first = ProjectNameGenerator.generate(vibe: "dark", tags: ["club"], variation: 1)
        let second = ProjectNameGenerator.generate(vibe: "dark", tags: ["club"], variation: 2)

        XCTAssertNotEqual(first, second)
    }

    func testUnknownTagsStillInfluenceResults() {
        let suggestions = ProjectNameGenerator.generate(vibe: "", tags: ["copper skyline"], count: 20)

        XCTAssertTrue(suggestions.contains { $0.localizedCaseInsensitiveContains("copper skyline") })
    }

    func testRhythmTagsCreateDifferentNamingWorlds() {
        let ukg = ProjectNameGenerator.generate(vibe: "", tags: ["UKG", "Gritty"], variation: 1)
        let fourByFour = ProjectNameGenerator.generate(vibe: "", tags: ["4x4", "Gritty"], variation: 1)

        XCTAssertNotEqual(ukg, fourByFour)
    }

    func testWorldHistoryReturnsToTheExactPreviousBatch() {
        let first = ProjectNameWorld(tags: ["Dreamy"], suggestions: ["Soft Focus"])
        let second = ProjectNameWorld(tags: ["UKG", "Sad"], suggestions: ["Blue Shuffle"])
        var history = ProjectNameWorldHistory()

        history.add(first)
        history.add(second)

        XCTAssertTrue(history.canGoBack)
        XCTAssertEqual(history.goBack(), first)
        XCTAssertEqual(history.position, 1)
    }

    func testGeneratingAfterGoingBackCreatesANewBranch() {
        let first = ProjectNameWorld(tags: ["Dreamy"], suggestions: ["Soft Focus"])
        let abandoned = ProjectNameWorld(tags: ["Dark"], suggestions: ["Black Static"])
        let replacement = ProjectNameWorld(tags: ["Happy"], suggestions: ["Bright Morning"])
        var history = ProjectNameWorldHistory()

        history.add(first)
        history.add(abandoned)
        history.goBack()
        history.add(replacement)

        XCTAssertEqual(history.worlds, [first, replacement])
        XCTAssertEqual(history.current, replacement)
    }
}
