import Foundation
import AVFoundation

enum AudioSliceExporter {
    static var slicesDirectory: URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("goodvibrationsHQ", isDirectory: true)
            .appendingPathComponent("Slices", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func formatTimeTag(seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d.%02d", m, s)
    }

    static func sanitizedFileName(baseName: String, startSeconds: Double, endSeconds: Double) -> String {
        let safeBase = baseName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\0", with: "")
        let safeName = safeBase.isEmpty ? "Track" : safeBase
        let startTag = formatTimeTag(seconds: startSeconds)
        let endTag = formatTimeTag(seconds: endSeconds)
        return "\(safeName) [\(startTag)-\(endTag)].wav"
    }

    /// Slices an audio file between startFraction and endFraction (both 0.0 ... 1.0) and writes out an uncompressed 24-bit PCM WAV.
    /// Returns the URL to the exported slice in the temporary slices cache.
    @discardableResult
    static func exportWavSlice(
        sourceURL: URL,
        startFraction: Double,
        endFraction: Double,
        baseName: String,
        duration: Double? = nil
    ) throws -> URL {
        let sourceFile = try AVAudioFile(forReading: sourceURL)
        let processingFormat = sourceFile.processingFormat
        let totalFrames = sourceFile.length

        guard totalFrames > 0 else {
            throw NSError(domain: "AudioSliceExporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Source audio file contains no frames."])
        }

        let clampedStart = max(0.0, min(1.0, min(startFraction, endFraction)))
        let clampedEnd = max(0.0, min(1.0, max(startFraction, endFraction)))

        let startFrame = AVAudioFramePosition(Double(totalFrames) * clampedStart)
        let endFrame = AVAudioFramePosition(Double(totalFrames) * clampedEnd)
        let framesToRead = endFrame - startFrame

        guard framesToRead > 0 else {
            throw NSError(domain: "AudioSliceExporter", code: -2, userInfo: [NSLocalizedDescriptionKey: "Requested slice range is empty."])
        }

        let totalDuration = duration ?? (Double(totalFrames) / processingFormat.sampleRate)
        let startSeconds = clampedStart * totalDuration
        let endSeconds = clampedEnd * totalDuration

        let fileName = sanitizedFileName(baseName: baseName, startSeconds: startSeconds, endSeconds: endSeconds)
        let outputURL = slicesDirectory.appendingPathComponent(fileName)

        // If file already exists and has matching size, return it directly
        if FileManager.default.fileExists(atPath: outputURL.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
           let size = attrs[.size] as? Int64, size > 1024 {
            return outputURL
        }

        sourceFile.framePosition = startFrame

        let wavSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: processingFormat.sampleRate,
            AVNumberOfChannelsKey: processingFormat.channelCount,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        do {
            let destinationFile = try AVAudioFile(
                forWriting: outputURL,
                settings: wavSettings,
                commonFormat: processingFormat.commonFormat,
                interleaved: processingFormat.isInterleaved
            )

            let chunkSize: AVAudioFrameCount = 32_768
            var remainingFrames = framesToRead

            while remainingFrames > 0 {
                let chunkFrames = AVAudioFrameCount(min(Int64(chunkSize), remainingFrames))
                guard let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: chunkFrames) else { break }
                try sourceFile.read(into: buffer, frameCount: chunkFrames)
                if buffer.frameLength == 0 { break }
                try destinationFile.write(from: buffer)
                remainingFrames -= Int64(buffer.frameLength)
            }
        }

        return outputURL
    }
}
