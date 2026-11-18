import SwiftUI

/// Static, refined phase badge for the floating minibar.
/// Displays the current workflow phase in calm, high-contrast green for personal projects
/// and orange for client projects without moving text.
struct FloatingPhaseTickerView: View {
    let phase: ProductionPhase
    let isClient: Bool
    let size: PetPuckSize
    var customWidth: CGFloat? = nil
    var onNextPhase: (() -> Void)? = nil

    @State private var isHovered = false

    private var themeColor: Color {
        isClient ? Color(hex: "FB923C") : Color(hex: "34D399")
    }

    private var tickerWidth: CGFloat {
        if let custom = customWidth {
            return custom
        }
        switch size {
        case .small: return 230
        case .medium: return 268
        case .large: return 308
        case .extraLarge: return 348
        }
    }

    private var tickerHeight: CGFloat {
        switch size {
        case .small: return 17
        case .medium: return 19
        case .large: return 22
        case .extraLarge: return 25
        }
    }

    private var fontSize: CGFloat {
        switch size {
        case .small: return 7.5
        case .medium: return 8.0
        case .large: return 9.0
        case .extraLarge: return 10.0
        }
    }

    var body: some View {
        Button {
            onNextPhase?()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(themeColor)
                    .frame(width: 4, height: 4)

                Text(phase.rawValue)
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(themeColor)
                    .lineLimit(1)
            }
            .frame(width: tickerWidth, height: tickerHeight)
            .background(
                Capsule()
                    .fill(Color(hex: "111418").opacity(0.92))
            )
            .background(
                Capsule()
                    .fill(themeColor.opacity(isHovered ? 0.18 : 0.08))
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(themeColor.opacity(isHovered ? 0.55 : 0.28), lineWidth: 0.8)
            )
            .shadow(color: themeColor.opacity(isHovered ? 0.25 : 0.06), radius: isHovered ? 2 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Workflow Phase: \(phase.rawValue) (\(isClient ? "Client Project" : "Personal Project")) — Click to advance phase")
    }
}
