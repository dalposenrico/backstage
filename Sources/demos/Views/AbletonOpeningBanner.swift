import SwiftUI

struct AbletonOpeningBanner: View {
    let opening: AbletonOpeningState
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if opening.phase == .opening {
                ProgressView()
                    .controlSize(.small)
                Text("Opening \(opening.projectName) in Ableton Live…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primaryText)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.green)
                Text("\(opening.projectName) is open in Ableton Live")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primaryText)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondaryText)
                    .padding(3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.elevatedBg, in: Capsule())
        .overlay(
            Capsule()
                .stroke(
                    opening.phase == .opening
                        ? Color.accent.opacity(0.4)
                        : Color.green.opacity(0.4),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}
