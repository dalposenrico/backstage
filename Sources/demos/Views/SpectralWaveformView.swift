import SwiftUI

struct SpectralWaveformView: View {
    let samples: [SpectralWaveformSample]
    let playedFraction: Double?
    var hoverFraction: Double? = nil
    var sectionMarkers: [Double] = []

    var body: some View {
        Canvas { context, size in
            guard samples.isEmpty == false else { return }
            let centerY = size.height / 2
            let halfHeight = max(1, centerY - 1)
            let step = size.width / CGFloat(samples.count)
            let visibleCount = max(1, Int(size.width / 1.25))
            let stride = max(1, samples.count / visibleCount)

            for index in Swift.stride(from: 0, to: samples.count, by: stride) {
                let sample = samples[index]
                guard sample.amplitude > 0.001 else { continue }
                let x = CGFloat(index) / CGFloat(max(1, samples.count - 1)) * size.width
                let height = max(1.5, CGFloat(sample.amplitude) * halfHeight)
                let energy = max(0.001, sample.low + sample.mid + sample.high)
                let low = Double(min(1, sample.low / energy))
                let mid = Double(min(1, sample.mid / energy))
                let high = Double(min(1, sample.high / energy))
                let color = Color(
                    red: min(1, 0.12 + low * 1.15 + mid * 0.08),
                    green: min(1, 0.34 + mid * 0.85 + high * 0.18),
                    blue: min(1, 0.48 + high * 0.95 + mid * 0.32)
                )
                let fraction = Double(index) / Double(max(1, samples.count - 1))
                let opacity = playedFraction.map { fraction <= $0 ? 1.0 : 0.38 } ?? 0.72
                var path = Path()
                path.move(to: CGPoint(x: x, y: centerY - height))
                path.addLine(to: CGPoint(x: x, y: centerY + height))
                context.stroke(
                    path,
                    with: .color(color.opacity(opacity)),
                    lineWidth: max(1, step * CGFloat(stride) * 0.72)
                )
            }

            var center = Path()
            center.move(to: CGPoint(x: 0, y: centerY))
            center.addLine(to: CGPoint(x: size.width, y: centerY))
            context.stroke(center, with: .color(.white.opacity(0.10)), lineWidth: 0.5)

            for markerFraction in sectionMarkers {
                let x = CGFloat(min(max(markerFraction, 0), 1)) * size.width
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(
                    line,
                    with: .color(Color.accent.opacity(0.55)),
                    style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                )
            }

            if let playedFraction {
                drawMarker(at: playedFraction, color: .white, in: &context, size: size, width: 1.5)
            }
            if let hoverFraction {
                drawMarker(at: hoverFraction, color: .white.opacity(0.55), in: &context, size: size, width: 1)
            }
        }
    }

    private func drawMarker(
        at fraction: Double,
        color: Color,
        in context: inout GraphicsContext,
        size: CGSize,
        width: CGFloat
    ) {
        let x = CGFloat(min(max(fraction, 0), 1)) * size.width
        var marker = Path()
        marker.move(to: CGPoint(x: x, y: 0))
        marker.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(marker, with: .color(color), lineWidth: width)
    }
}
