import XCTest
@testable import demos

final class StreamingReferenceTests: XCTestCase {
    func testSpotifyPlaylistBecomesEmbedURL() {
        let reference = StreamingReference.make(
            title: "Mix direction",
            urlText: "https://open.spotify.com/playlist/abc123?si=xyz"
        )

        XCTAssertEqual(reference?.service, .spotify)
        XCTAssertEqual(reference?.embedURL?.absoluteString, "https://open.spotify.com/embed/playlist/abc123?si=xyz")
    }

    func testAppleMusicPlaylistBecomesEmbedURL() {
        let reference = StreamingReference.make(
            title: "",
            urlText: "https://music.apple.com/nl/playlist/example/pl.u-123"
        )

        XCTAssertEqual(reference?.service, .appleMusic)
        XCTAssertEqual(reference?.title, "Apple Music reference")
        XCTAssertEqual(reference?.embedURL?.host, "embed.music.apple.com")
    }

    func testUnsupportedAndInsecureLinksAreRejected() {
        XCTAssertNil(StreamingReference.make(title: "Nope", urlText: "https://example.com/playlist/123"))
        XCTAssertNil(StreamingReference.make(title: "Nope", urlText: "http://open.spotify.com/playlist/123"))
    }
}
