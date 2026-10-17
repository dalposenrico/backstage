import Foundation
import AVFoundation

struct LoudnessResult: Sendable {
    let integratedLUFS: Double
    let samplePeakDBFS: Double
}

enum LoudnessAnalyzer {
    static func analyze(_ url: URL, startFraction: Double = 0, endFraction: Double = 1) async -> LoudnessResult? {
        await Task.detached(priority: .utility) { analyzeSync(url, startFraction: startFraction, endFraction: endFraction) }.value
    }

    private static func analyzeSync(_ url: URL, startFraction: Double, endFraction: Double) -> LoudnessResult? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let channels = Int(format.channelCount)
        guard channels > 0 else { return nil }

        let sampleRate = format.sampleRate
        let blockFrames = max(1, Int(sampleRate * 0.400))
        let stepFrames = max(1, blockFrames / 4)
        var channelSamples = Array(repeating: [Float](), count: channels)
        var peak: Float = 0
        let chunk: AVAudioFrameCount = 32_768
        let startFrame = AVAudioFramePosition(Double(file.length) * max(0, min(1, startFraction)))
        let endFrame = AVAudioFramePosition(Double(file.length) * max(0, min(1, endFraction)))
        file.framePosition = min(startFrame, file.length)

        while file.framePosition < min(file.length, endFrame) {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { break }
            let remaining = min(Int64(chunk), min(file.length, endFrame) - file.framePosition)
            do { try file.read(into: buffer, frameCount: AVAudioFrameCount(max(0, remaining))) } catch { return nil }
            guard let data = buffer.floatChannelData else { return nil }
            let count = Int(buffer.frameLength)
            if count == 0 { break }
            for channel in 0..<channels {
                channelSamples[channel].reserveCapacity(channelSamples[channel].count + count)
                for index in 0..<count {
                    let sample = data[channel][index]
                    channelSamples[channel].append(sample)
                    peak = max(peak, abs(sample))
                }
            }
        }

        var filtered = channelSamples
        for channel in 0..<channels {
            applyBiquad(&filtered[channel], coefficients: highShelf(sampleRate: sampleRate))
            applyBiquad(&filtered[channel], coefficients: highPass(sampleRate: sampleRate))
        }
        guard let sampleCount = filtered.first?.count, sampleCount > 0 else { return nil }

        var blocks: [Double] = []
        var start = 0
        while start < sampleCount {
            let end = min(sampleCount, start + blockFrames)
            guard end - start >= min(blockFrames, stepFrames) else { break }
            var energy = 0.0
            for channel in 0..<channels {
                var sum = 0.0
                for index in start..<end {
                    let value = Double(filtered[channel][index])
                    sum += value * value
                }
                energy += sum / Double(end - start)
            }
            blocks.append(energy)
            start += stepFrames
        }

        let absolute = blocks.filter { loudness($0) > -70 }
        guard !absolute.isEmpty else { return nil }
        let absoluteMean = absolute.reduce(0, +) / Double(absolute.count)
        let relativeGate = loudness(absoluteMean) - 10
        let gated = absolute.filter { loudness($0) > relativeGate }
        guard !gated.isEmpty else { return nil }
        let integrated = loudness(gated.reduce(0, +) / Double(gated.count))
        let peakDB = peak > 0 ? 20 * log10(Double(peak)) : -.infinity
        return LoudnessResult(integratedLUFS: integrated, samplePeakDBFS: peakDB)
    }

    private static func loudness(_ energy: Double) -> Double {
        energy > 0 ? -0.691 + 10 * log10(energy) : -.infinity
    }

    private struct Biquad { let b0, b1, b2, a1, a2: Double }

    private static func applyBiquad(_ samples: inout [Float], coefficients c: Biquad) {
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for index in samples.indices {
            let x = Double(samples[index])
            let y = c.b0*x + c.b1*x1 + c.b2*x2 - c.a1*y1 - c.a2*y2
            samples[index] = Float(y)
            x2 = x1; x1 = x; y2 = y1; y1 = y
        }
    }

    private static func highPass(sampleRate: Double) -> Biquad {
        let f0 = 38.13547087602444, q = 0.5003270373238773
        let w0 = 2 * Double.pi * f0 / sampleRate
        let alpha = sin(w0) / (2 * q), cosw = cos(w0), a0 = 1 + alpha
        return Biquad(b0: ((1 + cosw) / 2) / a0, b1: (-(1 + cosw)) / a0,
                      b2: ((1 + cosw) / 2) / a0, a1: (-2 * cosw) / a0, a2: (1 - alpha) / a0)
    }

    private static func highShelf(sampleRate: Double) -> Biquad {
        let f0 = 1681.974450955533, gain = 3.999843853973347
        let a = pow(10, gain / 40), w0 = 2 * Double.pi * f0 / sampleRate
        let cosw = cos(w0), sinw = sin(w0), alpha = sinw / 2 * sqrt(2), rootA = sqrt(a)
        let a0 = (a + 1) - (a - 1) * cosw + 2 * rootA * alpha
        return Biquad(
            b0: a * ((a + 1) + (a - 1) * cosw + 2 * rootA * alpha) / a0,
            b1: -2 * a * ((a - 1) + (a + 1) * cosw) / a0,
            b2: a * ((a + 1) + (a - 1) * cosw - 2 * rootA * alpha) / a0,
            a1: 2 * ((a - 1) - (a + 1) * cosw) / a0,
            a2: ((a + 1) - (a - 1) * cosw - 2 * rootA * alpha) / a0
        )
    }
}
