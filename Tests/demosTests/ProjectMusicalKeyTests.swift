import XCTest
@testable import demos

final class ProjectMusicalKeyTests: XCTestCase {
    func testParsesSeparatedKeyComponents() {
        XCTAssertEqual(
            ProjectMusicalKeys.selection(from: "F♯ minor"),
            ProjectMusicalKeySelection(note: "F", accidental: .sharp, mode: .minor)
        )
        XCTAssertEqual(
            ProjectMusicalKeys.selection(from: "B♭ major"),
            ProjectMusicalKeySelection(note: "B", accidental: .flat, mode: .major)
        )
    }

    func testMigratesLegacyEnharmonicDisplayToFirstSpelling() {
        XCTAssertEqual(
            ProjectMusicalKeys.selection(from: "C♯/D♭ major"),
            ProjectMusicalKeySelection(note: "C", accidental: .sharp, mode: .major)
        )
    }

    func testParsesExtendedAbletonScaleModes() {
        XCTAssertEqual(
            ProjectMusicalKeys.selection(from: "E Phrygian Dominant")?.mode,
            .phrygianDominant
        )
        XCTAssertEqual(
            ProjectMusicalKeys.selection(from: "C♯ Half-whole Diminished")?.mode,
            .halfWholeDiminished
        )
        XCTAssertEqual(
            ProjectMusicalKeys.selection(from: "B♭ Messiaen 7")?.mode,
            .messiaenSeven
        )
    }

    func testEveryModeRoundTripsThroughDisplayName() {
        for mode in ProjectKeyMode.allCases {
            let selection = ProjectMusicalKeySelection(note: "F", accidental: .sharp, mode: mode)
            XCTAssertEqual(ProjectMusicalKeys.selection(from: selection.displayName), selection)
        }
    }

    func testRejectsMissingOrUnrecognizedKeys() {
        XCTAssertNil(ProjectMusicalKeys.selection(from: nil))
        XCTAssertNil(ProjectMusicalKeys.selection(from: "12A"))
    }
}
