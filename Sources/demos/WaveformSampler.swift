import Foundation
import AVFoundation

struct SpectralWaveformSample: Sendable {
    let amplitude: Float
    let low: Float
    let mid: Float
    let high: Float
}

enum WaveformSampler {
    static func samples(for url: URL, count: Int = 240) async -> [Float] {
        await spectralSamples(for: url, count: count).map(\.amplitude)
    }

    /// Produces a compact, frequency-coloured overview without retaining or
    /// rewriting audio. The simple crossover filters are intentionally cheaper
    /// than an FFT so several compare rows can be prepared in the background.
    static func spectralSamples(for url: URL, count: Int = 720) async -> [SpectralWaveformSample] {
        await Task.detached(priority: .utility) {
            guard let file = try? AVAudioFile(forReading: url) else { return [] }
            let format = file.processingFormat
            let total = max(1, Int(file.length))
            let framesPerBin = max(1, total / count)
            var fullPeaks = [Float](repeating: 0, count: count)
            var lowPeaks = [Float](repeating: 0, count: count)
            var midPeaks = [Float](repeating: 0, count: count)
            var highPeaks = [Float](repeating: 0, count: count)
            let chunk: AVAudioFrameCount = 16_384
            var frameIndex = 0
            var lowState: Float = 0
            var highSmoothingState: Float = 0
            let sampleRate = Float(max(1, format.sampleRate))
            let lowCoefficient = min(1, 2 * Float.pi * 220 / sampleRate)
            let highCoefficient = min(1, 2 * Float.pi * 3_200 / sampleRate)

            while file.framePosition < file.length {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { break }
                do { try file.read(into: buffer, frameCount: chunk) } catch { break }
                guard let channels = buffer.floatChannelData else { break }
                for index in 0..<Int(buffer.frameLength) {
                    let bin = min(count - 1, frameIndex / framesPerBin)
                    var mono: Float = 0
                    for channel in 0..<Int(format.channelCount) {
                        mono += channels[channel][index]
                    }
                    mono /= Float(max(1, Int(format.channelCount)))

                    lowState += lowCoefficient * (mono - lowState)
                    highSmoothingState += highCoefficient * (mono - highSmoothingState)
                    let low = abs(lowState)
                    let high = abs(mono - highSmoothingState)
                    let mid = abs(highSmoothingState - lowState)

                    fullPeaks[bin] = max(fullPeaks[bin], abs(mono))
                    lowPeaks[bin] = max(lowPeaks[bin], low)
                    midPeaks[bin] = max(midPeaks[bin], mid)
                    highPeaks[bin] = max(highPeaks[bin], high)
                    frameIndex += 1
                }
            }

            let maximum = fullPeaks.max() ?? 0
            guard maximum > 0.001 else {
                return [SpectralWaveformSample](
                    repeating: SpectralWaveformSample(amplitude: 0, low: 0, mid: 0, high: 0),
                    count: count
                )
            }
            return fullPeaks.indices.map { index in
                let amp = fullPeaks[index]
                if amp < 0.001 {
                    return SpectralWaveformSample(amplitude: 0, low: 0, mid: 0, high: 0)
                }
                return SpectralWaveformSample(
                    amplitude: min(1.0, amp / maximum),
                    low: min(1.0, lowPeaks[index] / maximum),
                    mid: min(1.0, midPeaks[index] / maximum),
                    high: min(1.0, highPeaks[index] / maximum)
                )
            }
        }.value
    }
}
