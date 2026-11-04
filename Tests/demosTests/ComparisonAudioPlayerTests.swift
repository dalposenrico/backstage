import XCTest
@testable import demos

@MainActor
final class ComparisonAudioPlayerTests: XCTestCase {

    func testVersionLetters() {
        XCTAssertEqual(ComparisonAudioPlayer.versionLetter(for: 0), "A")
        XCTAssertEqual(ComparisonAudioPlayer.versionLetter(for: 1), "B")
        XCTAssertEqual(ComparisonAudioPlayer.versionLetter(for: 2), "C")
        XCTAssertEqual(ComparisonAudioPlayer.versionLetter(for: 3), "D")
    }

    func testInitialState() {
        let player = ComparisonAudioPlayer()
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(player.activeSource)
        XCTAssertNil(player.previousSource)
        XCTAssertEqual(player.volume, 1.0)
        XCTAssertTrue(player.gainMatch)
        XCTAssertFalse(player.sectionMode)
        XCTAssertEqual(player.currentTime, 0)
        XCTAssertEqual(player.progress, 0)
    }

    func testABSwitchingOrderAndTracking() {
        let player = ComparisonAudioPlayer()
        let urlA = URL(fileURLWithPath: "/tmp/fake_version_a.wav")
        let urlB = URL(fileURLWithPath: "/tmp/fake_version_b.wav")
        let urlC = URL(fileURLWithPath: "/tmp/fake_version_c.wav")

        let sourceA = CompareSource(url: urlA, name: "Version A", kind: "Export", exportedAt: Date(), isReference: false)
        let sourceB = CompareSource(url: urlB, name: "Version B", kind: "Export", exportedAt: Date(), isReference: false)
        let sourceC = CompareSource(url: urlC, name: "Version C", kind: "Export", exportedAt: Date(), isReference: false)
        let all = [sourceA, sourceB, sourceC]

        // Switch to A
        player.switchTo(sourceA, allSources: all, loudnessResults: [:], keepPosition: false, playImmediately: false)
        XCTAssertEqual(player.activeSource, sourceA)
        XCTAssertNil(player.previousSource)

        // Switch to B
        player.switchTo(sourceB, allSources: all, loudnessResults: [:], keepPosition: false, playImmediately: false)
        XCTAssertEqual(player.activeSource, sourceB)
        XCTAssertEqual(player.previousSource, sourceA)

        // Instant A/B toggle should switch back to A
        player.toggleAB(allSources: all, loudnessResults: [:])
        XCTAssertEqual(player.activeSource, sourceA)
        XCTAssertEqual(player.previousSource, sourceB)

        // Instant A/B toggle again should switch to B
        player.toggleAB(allSources: all, loudnessResults: [:])
        XCTAssertEqual(player.activeSource, sourceB)
        XCTAssertEqual(player.previousSource, sourceA)

        // Next should cycle to C
        player.switchNext(allSources: all, loudnessResults: [:])
        XCTAssertEqual(player.activeSource, sourceC)

        // Next from C should cycle back to A
        player.switchNext(allSources: all, loudnessResults: [:])
        XCTAssertEqual(player.activeSource, sourceA)

        // Previous from A should cycle to C
        player.switchPrevious(allSources: all, loudnessResults: [:])
        XCTAssertEqual(player.activeSource, sourceC)
    }

    func testConvenienceOverloads() {
        let player = ComparisonAudioPlayer()
        let urlA = URL(fileURLWithPath: "/tmp/fake_a.wav")
        let urlB = URL(fileURLWithPath: "/tmp/fake_b.wav")
        let sourceA = CompareSource(url: urlA, name: "A", kind: "Export", exportedAt: nil, isReference: false)
        let sourceB = CompareSource(url: urlB, name: "B", kind: "Export", exportedAt: nil, isReference: false)
        player.sources = [sourceA, sourceB]

        player.switchTo(sourceA, keepPosition: false, playImmediately: false)
        XCTAssertEqual(player.activeSource, sourceA)

        player.switchNext()
        XCTAssertEqual(player.activeSource, sourceB)

        player.toggleAB()
        XCTAssertEqual(player.activeSource, sourceA)
    }

    func testGainMatchingCalculation() {
        let player = ComparisonAudioPlayer()
        let urlA = URL(fileURLWithPath: "/tmp/fake_loud.wav")
        let urlB = URL(fileURLWithPath: "/tmp/fake_quiet.wav")

        let sourceA = CompareSource(url: urlA, name: "Loud", kind: "Export", exportedAt: nil, isReference: false)
        let sourceB = CompareSource(url: urlB, name: "Quiet", kind: "Export", exportedAt: nil, isReference: false)
        let all = [sourceA, sourceB]

        // Quiet is -14 LUFS, Loud is -8 LUFS (difference is -6 dB)
        let loudness: [String: LoudnessResult] = [
            urlA.path: LoudnessResult(integratedLUFS: -8.0, samplePeakDBFS: -0.1),
            urlB.path: LoudnessResult(integratedLUFS: -14.0, samplePeakDBFS: -1.0)
        ]

        player.gainMatch = true
        player.switchTo(sourceA, allSources: all, loudnessResults: loudness, keepPosition: false, playImmediately: false)
        // Loud version should be attenuated by -6 dB to match quiet version (-14 - (-8) = -6)
        XCTAssertEqual(player.appliedGainDB, -6.0, accuracy: 0.01)

        player.switchTo(sourceB, allSources: all, loudnessResults: loudness, keepPosition: false, playImmediately: false)
        // Quiet version target is -14, current is -14, gain should be 0 dB
        XCTAssertEqual(player.appliedGainDB, 0.0, accuracy: 0.01)

        // If gain match is turned off
        player.setGainMatch(false, loudnessResults: loudness)
        XCTAssertEqual(player.appliedGainDB, 0.0)
    }

    func testVolumeClamping() {
        let player = ComparisonAudioPlayer()
        player.setVolume(1.5)
        XCTAssertEqual(player.volume, 1.0)
        player.setVolume(-0.5)
        XCTAssertEqual(player.volume, 0.0)
        player.setVolume(0.7)
        XCTAssertEqual(player.volume, 0.7, accuracy: 0.001)
    }
}
