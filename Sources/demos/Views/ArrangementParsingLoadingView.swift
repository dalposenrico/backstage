import SwiftUI

/// Animated, continuous visualizer displayed while parsing an Ableton Live set arrangement.
/// Features a real-time audio equalizer wave, continuous shimmering progress bar,
/// and live track extraction status so users know parsing is actively progressing.
struct ArrangementParsingLoadingView: View {
    let progress: Double
    let status: String

    @State private var isAnimatingBars = false
    @State private var shimmerOffset: CGFloat = -0.5

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                // Header: Animated Icon + Title + Animated Equalizer + Percentage
                HStack(spacing: 10) {
                    if #available(macOS 14.0, *) {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.accent)
                            .symbolEffect(.variableColor.iterative.reversing)
                    } else {
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.accent)
                    }

                    Text("Parsing Arrangement")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primaryText)

                    Spacer()

                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.accent)
                }

                // Shimmering Continuous Progress Bar
                shimmeringProgressBar

                // Status with pulsing activity dot
                HStack(spacing: 7) {
                    Circle()
                        .fill(Color.accent)
                        .frame(width: 6, height: 6)
                        .scaleEffect(isAnimatingBars ? 1.25 : 0.75)
                        .opacity(isAnimatingBars ? 1.0 : 0.35)
                        .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: isAnimatingBars)

                    Text(status)
                        .font(.system(size: 11))
                        .foregroundColor(.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(width: 380)
            .background(Color.sidebarBg.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isAnimatingBars = true
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                shimmerOffset = 1.5
            }
        }
    }

    // MARK: - Shimmering Progress Bar
    private var shimmeringProgressBar: some View {
        GeometryReader { geo in
            let totalW = geo.size.width
            let fillW = max(6, totalW * CGFloat(min(1.0, max(0.0, progress))))

            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 6)

                // Fill with subtle gradient
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [Color.accent.opacity(0.85), Color.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillW, height: 6)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: progress)

                // Continuous sweeping shimmer
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .white.opacity(0.6), location: 0.5),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: totalW * 0.4, height: 6)
                    .offset(x: totalW * shimmerOffset)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 6)
    }
}
