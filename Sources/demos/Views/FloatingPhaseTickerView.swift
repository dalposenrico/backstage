import AppKit
import SwiftUI

/// Horizontal scrolling marquee ticker for project workflow phases.
/// Styled in vibrant green for personal projects and vibrant orange for client projects.
struct FloatingPhaseTickerView: View {
    let phase: ProductionPhase
    let isClient: Bool
    let size: PetPuckSize
    var onNextPhase: (() -> Void)? = nil

    @State private var isHovered = false

    private var themeColor: Color {
        isClient ? Color(hex: "FB923C") : Color(hex: "4ADE80")
    }

    private var tickerWidth: CGFloat {
        switch size {
        case .small: return 84
        case .medium: return 96
        case .large: return 110
        case .extraLarge: return 124
        }
    }

    private var tickerHeight: CGFloat {
        size.capsuleHeight * 0.58
    }

    private var fontSize: CGFloat {
        switch size {
        case .small: return 8.5
        case .medium: return 9.0
        case .large: return 10.0
        case .extraLarge: return 11.5
        }
    }

    var body: some View {
        Button {
            onNextPhase?()
        } label: {
            ZStack {
                // Background capsule
                Capsule()
                    .fill(themeColor.opacity(isHovered ? 0.22 : 0.13))

                // Marquee scrolling text
                ContinuousMarqueeText(
                    text: "\(phase.rawValue) • ",
                    color: themeColor,
                    fontSize: fontSize,
                    containerWidth: tickerWidth
                )
                .padding(.horizontal, 6)
            }
            .frame(width: tickerWidth, height: tickerHeight)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(themeColor.opacity(isHovered ? 0.65 : 0.38), lineWidth: 0.9)
            )
            .shadow(color: themeColor.opacity(isHovered ? 0.35 : 0.15), radius: isHovered ? 3 : 1.5)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Workflow Phase: \(phase.rawValue) (\(isClient ? "Client Project" : "Personal Project")) — Click to advance phase")
    }
}

/// Continuous mathematical marquee text using monotonic TimelineView.
private struct ContinuousMarqueeText: View {
    let text: String
    let color: Color
    let fontSize: CGFloat
    let containerWidth: CGFloat

    private var cycleWidth: CGFloat {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .black)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let width = (text as NSString).size(withAttributes: attrs).width
        return max(width, 10)
    }

    // Number of repetitions needed to comfortably fill the container plus buffer
    private var copyCount: Int {
        let needed = Int(ceil(containerWidth / cycleWidth)) + 2
        return max(needed, 3)
    }

    var body: some View {
        let cycle = cycleWidth
        let copies = copyCount

        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let speed: Double = 26.0 // Points per second
            let offset = (elapsed * speed).truncatingRemainder(dividingBy: Double(cycle))

            HStack(spacing: 0) {
                ForEach(0..<copies, id: \.self) { _ in
                    Text(text)
                        .font(.system(size: fontSize, weight: .black, design: .monospaced))
                        .foregroundStyle(color)
                        .fixedSize()
                }
            }
            .offset(x: -CGFloat(offset))
            .frame(width: containerWidth, alignment: .leading)
            .clipped()
            .mask(
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [.clear, .black],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 6)

                    Rectangle().fill(Color.black)

                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 6)
                }
            )
        }
        .allowsHitTesting(false)
    }
}
