import XCTest
@testable import demos

final class AbletonLocatorTests: XCTestCase {
    func testParsesNamedLocatorsAnnotationsAndSortsByBeat() {
        let xml = """
        <Locators>
          <Locator Id="1">
            <Time Value="64" />
            <Name Value="Drop &amp; release" />
            <Annotation Value="Prefer the wider drums" />
          </Locator>
          <Locator Id="0">
            <Time Value="16.5" />
            <Name Value="Verse" />
            <Annotation Value="" />
          </Locator>
        </Locators>
        """

        XCTAssertEqual(
            AbletonProjectInspector.parseLocators(in: xml),
            [
                AbletonLocator(timeInBeats: 16.5, name: "Verse", annotation: ""),
                AbletonLocator(timeInBeats: 64, name: "Drop & release", annotation: "Prefer the wider drums")
            ]
        )
    }

    func testUnnamedLocatorGetsReadableFallbackAndInvalidTimeIsSkipped() {
        let xml = """
        <Locator Id="0"><Time Value="0" /><Name Value="" /></Locator>
        <Locator Id="1"><Time Value="nope" /><Name Value="Broken" /></Locator>
        """

        XCTAssertEqual(
            AbletonProjectInspector.parseLocators(in: xml),
            [AbletonLocator(timeInBeats: 0, name: "Ableton marker", annotation: "")]
        )
    }
}
