import XCTest
import AVFoundation
@testable import demos

final class AudioSliceExporterTests: XCTestCase {

    func testSanitizedFileName() {
        let name = AudioSliceExporter.sanitizedFileName(baseName: "My Cool/Track: Mix v1", startSeconds: 65, endSeconds: 92)
        XCTAssertEqual(name, "My Cool-Track- Mix v1 [01.05-01.32].wav")

        let emptyName = AudioSliceExporter.sanitizedFileName(baseName: "   ", startSeconds: 0, endSeconds: 15)
        XCTAssertEqual(emptyName, "Track [00.00-00.15].wav")
    }

    func testFormatTimeTag() {
        XCTAssertEqual(AudioSliceExporter.formatTimeTag(seconds: 0), "00.00")
        XCTAssertEqual(AudioSliceExporter.formatTimeTag(seconds: 4.8), "00.05")
        XCTAssertEqual(AudioSliceExporter.formatTimeTag(seconds: 75), "01.15")
        XCTAssertEqual(AudioSliceExporter.formatTimeTag(seconds: 3661), "61.01")
    }

    func testExportWavSliceExtractsCorrectDurationAndFormat() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Create a 2-second sine-wave / audio file (44100 Hz, stereo)
        let sampleRate: Double = 44100.0
        let totalFrames: AVAudioFrameCount = 88200 // 2.0 seconds
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            let audioFile = try AVAudioFile(forWriting: tempURL, settings: settings)
            let format = audioFile.processingFormat
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
                XCTFail("Failed to allocate buffer")
                return
            }
            buffer.frameLength = totalFrames
            if let data = buffer.floatChannelData {
                for i in 0..<Int(totalFrames) {
                    let sample = sin(Float(i) * 0.05) * 0.5
                    data[0][i] = sample
                    data[1][i] = sample
                }
            }
            try audioFile.write(from: buffer)
        }

        // Export slice from 0.25 to 0.75 (1.0 second, ~44100 frames)
        let sliceURL = try AudioSliceExporter.exportWavSlice(
            sourceURL: tempURL,
            startFraction: 0.25,
            endFraction: 0.75,
            baseName: "TestSlice",
            duration: 2.0
        )
        defer { try? FileManager.default.removeItem(at: sliceURL) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: sliceURL.path))
        XCTAssertTrue(sliceURL.lastPathComponent.hasPrefix("TestSlice [00.01-00.02]"))
        XCTAssertTrue(sliceURL.pathExtension.lowercased() == "wav")

        let exportedFile = try AVAudioFile(forReading: sliceURL)
        XCTAssertEqual(exportedFile.length, 44100)
        XCTAssertEqual(exportedFile.fileFormat.sampleRate, sampleRate)
        XCTAssertEqual(exportedFile.fileFormat.channelCount, 2)
    }

    func testExportWavSliceHandlesInvertedFractions() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let sampleRate: Double = 44100.0
        let totalFrames: AVAudioFrameCount = 44100
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        do {
            let audioFile = try AVAudioFile(forWriting: tempURL, settings: settings)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: totalFrames) else {
                XCTFail("Buffer failed")
                return
            }
            buffer.frameLength = totalFrames
            try audioFile.write(from: buffer)
        }

        // start > end: should still succeed by taking min and max
        let sliceURL = try AudioSliceExporter.exportWavSlice(
            sourceURL: tempURL,
            startFraction: 0.8,
            endFraction: 0.2,
            baseName: "Inverted",
            duration: 1.0
        )
        defer { try? FileManager.default.removeItem(at: sliceURL) }

        let exportedFile = try AVAudioFile(forReading: sliceURL)
        // 0.8 - 0.2 = 0.6 of 44100 = 26460 frames
        XCTAssertEqual(exportedFile.length, 26460)
    }
}
