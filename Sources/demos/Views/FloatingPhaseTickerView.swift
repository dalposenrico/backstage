import SwiftUI

/// Static, refined phase dropdown badge for the floating minibar.
/// Clicking opens a dropdown menu with checkmark selection for phases,
/// color-coded green for personal projects and orange for client projects.
struct FloatingPhaseTickerView: View {
    let phase: ProductionPhase
    let isClient: Bool
    let availablePhases: [ProductionPhase]
    let size: PetPuckSize
    var customWidth: CGFloat? = nil
    var onSelectPhase: ((ProductionPhase?) -> Void)? = nil
    var onToggleMode: (() -> Void)? = nil

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
        Menu {
            Section("Workflow Phase") {
                ForEach(availablePhases) { item in
                    Button {
                        onSelectPhase?(item)
                    } label: {
                        HStack {
                            Text(item.rawValue)
                            if item == phase {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Clear Phase (Smaller Floating Pill)") {
                onSelectPhase?(nil)
            }

            if let onToggleMode {
                Divider()
                Button(isClient ? "Switch to Personal Project (Green)" : "Switch to Client Project (Orange)") {
                    onToggleMode()
                }
            }
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

                Image(systemName: "chevron.down")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(themeColor.opacity(0.75))
            }
            .frame(width: tickerWidth, height: tickerHeight)
            .background(
                Capsule()
                    .fill(Color(hex: "111418").opacity(0.92))
            )
            .background(
                Capsule()
                    .fill(themeColor.opacity(isHovered ? 0.20 : 0.10))
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(themeColor.opacity(isHovered ? 0.60 : 0.32), lineWidth: 0.8)
            )
            .shadow(color: themeColor.opacity(isHovered ? 0.25 : 0.08), radius: isHovered ? 2 : 1)
        }
        .menuStyle(.borderlessButton)
        .onHover { isHovered = $0 }
        .help("Current Phase: \(phase.rawValue) — Click to choose phase")
    }
}
