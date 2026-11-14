import SwiftUI

struct SpectralWaveformView: View {
    let samples: [SpectralWaveformSample]
    let playedFraction: Double?
    var hoverFraction: Double? = nil
    var sectionMarkers: [Double] = []
    var zoomScale: CGFloat = 1.0
    var visibleCenterFraction: Double = 0.5

    var body: some View {
        Canvas { context, size in
            guard samples.isEmpty == false else { return }
            let zoom = max(1.0, Double(zoomScale))
            let windowWidth = 1.0 / zoom
            let halfWindow = windowWidth / 2.0
            let clampedCenter = min(max(visibleCenterFraction, halfWindow), 1.0 - halfWindow)
            let startFraction = max(0.0, clampedCenter - halfWindow)
            let endFraction = min(1.0, clampedCenter + halfWindow)
            let visibleRange = max(0.0001, endFraction - startFraction)

            let centerY = size.height / 2
            let halfHeight = max(1, centerY - 2)

            let visibleCount = max(1, Int(size.width / 1.15))
            let sampleStep = Double(samples.count) * visibleRange / Double(visibleCount)
            let stride = max(1, Int(sampleStep))
            let startIndex = max(0, Int(startFraction * Double(samples.count - 1)))
            let endIndex = min(samples.count, Int(ceil(endFraction * Double(samples.count - 1))) + 1)

            let barWidth = max(1.2, (size.width / CGFloat(max(1, (endIndex - startIndex) / stride))) * 0.78)

            for index in Swift.stride(from: startIndex, to: endIndex, by: stride) {
                let sample = samples[index]
                guard sample.amplitude > 0.001 else { continue }
                let fraction = Double(index) / Double(max(1, samples.count - 1))
                let normalizedX = (fraction - startFraction) / visibleRange
                guard normalizedX >= -0.02 && normalizedX <= 1.02 else { continue }
                let x = CGFloat(normalizedX) * size.width

                let height = max(1.5, CGFloat(sample.amplitude) * halfHeight)
                let energy = max(0.001, sample.low + sample.mid + sample.high)
                let low = Double(min(1, sample.low / energy))
                let mid = Double(min(1, sample.mid / energy))
                let high = Double(min(1, sample.high / energy))

                // Rekordbox 3-Band RGB Color Formulation:
                // Low (Bass/Sub/Kick): Electric Blue (RGB 0.05, 0.45, 1.0)
                // Mid (Vocals/Snare/Synths): Warm Amber/Orange (RGB 1.0, 0.58, 0.08)
                // High (Cymbals/Hats/Air): Crisp Ice White (RGB 0.92, 0.96, 1.0)
                let r = min(1.0, low * 0.06 + mid * 1.00 + high * 0.92)
                let g = min(1.0, low * 0.45 + mid * 0.58 + high * 0.96)
                let b = min(1.0, low * 1.00 + mid * 0.08 + high * 1.00)
                let color = Color(red: r, green: g, blue: b)

                let opacity = playedFraction.map { fraction <= $0 ? 1.0 : 0.40 } ?? 0.85
                var path = Path()
                path.move(to: CGPoint(x: x, y: centerY - height))
                path.addLine(to: CGPoint(x: x, y: centerY + height))
                context.stroke(
                    path,
                    with: .color(color.opacity(opacity)),
                    lineWidth: barWidth
                )
            }

            var center = Path()
            center.move(to: CGPoint(x: 0, y: centerY))
            center.addLine(to: CGPoint(x: size.width, y: centerY))
            context.stroke(center, with: .color(.white.opacity(0.12)), lineWidth: 0.5)

            for markerFraction in sectionMarkers {
                guard markerFraction >= startFraction && markerFraction <= endFraction else { continue }
                let x = CGFloat((markerFraction - startFraction) / visibleRange) * size.width
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(
                    line,
                    with: .color(Color.accent.opacity(0.65)),
                    style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])
                )
            }

            if let playedFraction, playedFraction >= startFraction && playedFraction <= endFraction {
                let x = CGFloat((playedFraction - startFraction) / visibleRange) * size.width
                // Subtle playhead glow
                drawMarker(atX: x, color: Color(red: 0.1, green: 0.5, blue: 1.0).opacity(0.4), in: &context, size: size, width: 4.0)
                drawMarker(atX: x, color: .white, in: &context, size: size, width: 2.0)
            }
            if let hoverFraction, hoverFraction >= startFraction && hoverFraction <= endFraction {
                let x = CGFloat((hoverFraction - startFraction) / visibleRange) * size.width
                drawMarker(atX: x, color: .white.opacity(0.6), in: &context, size: size, width: 1.2)
            }
        }
    }

    private func drawMarker(
        atX x: CGFloat,
        color: Color,
        in context: inout GraphicsContext,
        size: CGSize,
        width: CGFloat
    ) {
        var marker = Path()
        marker.move(to: CGPoint(x: x, y: 0))
        marker.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(marker, with: .color(color), lineWidth: width)
    }

    private func drawMarker(
        at fraction: Double,
        color: Color,
        in context: inout GraphicsContext,
        size: CGSize,
        width: CGFloat
    ) {
        let x = CGFloat(min(max(fraction, 0), 1)) * size.width
        drawMarker(atX: x, color: color, in: &context, size: size, width: width)
    }
}
