import SwiftUI

struct AbletonOpeningBanner: View {
    let opening: AbletonOpeningState
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if opening.phase == .opening {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text(opening.autoExportOnReady
                        ? "Opening \(opening.projectName) & exporting new version…"
                        : "Opening \(opening.projectName) in Ableton Live…")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primaryText)
                    if opening.autoExportOnReady {
                        Text("Save or discard changes in Ableton if prompted")
                            .font(.system(size: 10))
                            .foregroundColor(.secondaryText)
                    }
                }
            } else {
                Image(systemName: opening.autoExportOnReady ? "bolt.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(opening.autoExportOnReady ? .orange : .green)
                Text(opening.autoExportOnReady
                    ? "\(opening.projectName) is ready — starting version export…"
                    : "\(opening.projectName) is open in Ableton Live")
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
                        ? (opening.autoExportOnReady ? Color.orange.opacity(0.5) : Color.accent.opacity(0.4))
                        : (opening.autoExportOnReady ? Color.orange.opacity(0.6) : Color.green.opacity(0.4)),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}
