import XCTest
import AVFoundation
@testable import demos

final class WaveformSamplerTests: XCTestCase {

    func testSilentAudioFileProducesZeroAmplitudeWaveform() async throws {
        // Create a temporary silent WAV file (1 second, 44100 Hz, 16-bit stereo)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            let audioFile = try AVAudioFile(forWriting: tempURL, settings: settings)
            let format = audioFile.processingFormat
            let frameCount: AVAudioFrameCount = 44100
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                XCTFail("Could not create audio buffer")
                return
            }
            buffer.frameLength = frameCount // All zero bytes
            try audioFile.write(from: buffer)
        }

        // 1. Test WaveformSampler.samples
        let spectral = await WaveformSampler.spectralSamples(for: tempURL, count: 64)
        XCTAssertEqual(spectral.count, 64)
        for s in spectral {
            XCTAssertEqual(s.amplitude, 0.0, accuracy: 0.0001)
        }

        // 2. Test InlineWaveformCache
        let exp = expectation(description: "WaveformCache completion")
        InlineWaveformCache.shared.requestSamples(for: tempURL) { peaks in
            XCTAssertEqual(peaks.count, 32)
            for p in peaks {
                XCTAssertEqual(p, 0.0, accuracy: 0.0001, "Silent track peak must be 0.0")
            }
            exp.fulfill()
        }
        await fulfillment(of: [exp], timeout: 2.0)
    }

    func testAudibleAudioFileProducesNormalizedPeaks() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            let audioFile = try AVAudioFile(forWriting: tempURL, settings: settings)
            let format = audioFile.processingFormat
            let frameCount: AVAudioFrameCount = 44100
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                XCTFail("Could not create audio buffer")
                return
            }
            buffer.frameLength = frameCount

            // Put a 440 Hz sine wave with 0.8 amplitude into the buffer
            if let channels = buffer.floatChannelData {
                for ch in 0..<Int(format.channelCount) {
                    for i in 0..<Int(frameCount) {
                        channels[ch][i] = 0.8 * sin(2.0 * Float.pi * 440.0 * Float(i) / 44100.0)
                    }
                }
            }
            try audioFile.write(from: buffer)
        }

        let exp = expectation(description: "WaveformCache completion")
        InlineWaveformCache.shared.requestSamples(for: tempURL) { peaks in
            XCTAssertEqual(peaks.count, 32)
            let maxPeak = peaks.max() ?? 0.0
            XCTAssertGreaterThan(maxPeak, 0.5, "Audible file must have non-zero peaks")
            exp.fulfill()
        }
        await fulfillment(of: [exp], timeout: 2.0)
    }
}
